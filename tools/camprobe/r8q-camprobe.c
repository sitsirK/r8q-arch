// SPDX-License-Identifier: GPL-2.0-only
/*
 * r8q camera sensor prober.
 *
 * Samsung's downstream DT names none of the camera sensors: Qualcomm's camera
 * stack gets the part number, and for the two CCI modules even the I2C slave
 * address, from userspace. So the only way to find out what is actually fitted
 * is to power a module up and read its ID register -- and a sensor will not ACK
 * at all until its rails are on, its MCLK is running and XSHUTDOWN is released.
 * That is a driver's job, hence this one.
 *
 * It is a diagnostic, not a driver: it powers one camera module, reads a
 * handful of the register offsets the common vendors put their chip ID at,
 * prints what it found, and powers back down. Build it out-of-tree against the
 * r8q kernel and insmod it by hand; nothing autoloads it.
 *
 *   make -C <kernel out> M=$PWD modules
 *
 * Register offsets probed, all 16-bit big-endian reads:
 *   0x0000  MIPI CCS / SMIA++ model ID -- Samsung S5K*, Sony IMX*, OmniVision
 *   0x0016  Sony IMX chip ID on the parts that do not follow CCS
 *   0x0716  SK hynix Hi-8xx
 *   0x300a  OmniVision OVxxxx (8-bit reads, done separately)
 */

#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/property.h>
#include <linux/regulator/consumer.h>

#define CAMPROBE_MAX_ADDRS	16

/*
 * hold=1: stay bound with the rails and MCLK on instead of powering back down
 * and failing the probe. That keeps a module alive so its chips can be poked
 * from userspace with i2ctransfer(8) -- which is the only way to work out what
 * a write-only part like a VCM actuator actually is, since none of the in-tree
 * VCM drivers can be instantiated via new_device (they have no i2c id_table)
 * and all of them need real regulators.
 */
static bool hold;
module_param(hold, bool, 0444);
MODULE_PARM_DESC(hold, "keep the module powered and stay bound");

static const char * const camprobe_supply_names[] = {
	"vddio", "avdd", "dvdd",
};

static const u16 camprobe_id_regs16[] = {
	0x0000, 0x0002, 0x0016, 0x0716,
};

struct camprobe {
	struct device *dev;
	struct i2c_adapter *adap;
	struct clk *mclk;
	struct gpio_desc *reset;
	struct regulator_bulk_data supplies[ARRAY_SIZE(camprobe_supply_names)];
	u32 addrs[CAMPROBE_MAX_ADDRS];
	int naddrs;
};

/* 16-bit register pointer, big endian, then n bytes back. */
static int camprobe_read(struct camprobe *cp, u16 addr, u16 reg, u8 *buf, int n)
{
	u8 wb[2] = { reg >> 8, reg & 0xff };
	struct i2c_msg msgs[2] = {
		{ .addr = addr, .flags = 0,        .len = 2, .buf = wb  },
		{ .addr = addr, .flags = I2C_M_RD, .len = n, .buf = buf },
	};
	int ret;

	ret = i2c_transfer(cp->adap, msgs, 2);
	if (ret != 2)
		return ret < 0 ? ret : -EIO;

	return 0;
}

static void camprobe_scan_one(struct camprobe *cp, u16 addr)
{
	bool acked = false;
	unsigned int i;
	u8 buf[2];
	int ret;

	for (i = 0; i < ARRAY_SIZE(camprobe_id_regs16); i++) {
		ret = camprobe_read(cp, addr, camprobe_id_regs16[i], buf, 2);
		if (ret) {
			/* Only shout about the first register: a NACK there
			 * means nothing is fitted at this address, and the
			 * remaining reads would just repeat it (and on geni
			 * each NACK costs about a second).
			 */
			if (i == 0) {
				u8 b;
				struct i2c_msg m = { .addr = addr,
						     .flags = I2C_M_RD,
						     .len = 1, .buf = &b };

				/*
				 * Before giving up, try a bare one-byte read.
				 * A VCM actuator has no 16-bit register map to
				 * point at, so the read above tells us nothing
				 * about whether a chip is present; this does.
				 */
				if (i2c_transfer(cp->adap, &m, 1) == 1) {
					dev_info(cp->dev,
						 "0x%02x: ACKs a bare read (0x%02x) -- PRESENT, no 16-bit regmap\n",
						 addr, b);
					return;
				}
				dev_info(cp->dev, "0x%02x: no answer (%d)\n",
					 addr, ret);
				return;
			}
			dev_info(cp->dev, "0x%02x: reg 0x%04x read failed (%d)\n",
				 addr, camprobe_id_regs16[i], ret);
			continue;
		}
		acked = true;
		dev_info(cp->dev, "0x%02x: reg 0x%04x = 0x%02x%02x\n",
			 addr, camprobe_id_regs16[i], buf[0], buf[1]);
	}

	if (acked)
		dev_info(cp->dev, "0x%02x: ^^ SOMETHING IS FITTED HERE\n", addr);
}

static int camprobe_power_on(struct camprobe *cp)
{
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(cp->supplies), cp->supplies);
	if (ret)
		return ret;

	ret = clk_prepare_enable(cp->mclk);
	if (ret) {
		regulator_bulk_disable(ARRAY_SIZE(cp->supplies), cp->supplies);
		return ret;
	}

	dev_info(cp->dev, "powered: mclk %lu Hz\n",
		 cp->mclk ? clk_get_rate(cp->mclk) : 0);

	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(cp->reset, 0);
	usleep_range(20000, 21000);

	return 0;
}

static void camprobe_power_off(struct camprobe *cp)
{
	gpiod_set_value_cansleep(cp->reset, 1);
	clk_disable_unprepare(cp->mclk);
	regulator_bulk_disable(ARRAY_SIZE(cp->supplies), cp->supplies);
}

static int camprobe_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct device_node *bus;
	struct camprobe *cp;
	unsigned int i;
	int ret;

	cp = devm_kzalloc(dev, sizeof(*cp), GFP_KERNEL);
	if (!cp)
		return -ENOMEM;

	cp->dev = dev;

	bus = of_parse_phandle(dev->of_node, "i2c-bus", 0);
	if (!bus)
		return dev_err_probe(dev, -EINVAL, "no i2c-bus phandle\n");

	cp->adap = of_get_i2c_adapter_by_node(bus);
	of_node_put(bus);
	if (!cp->adap)
		return dev_err_probe(dev, -EPROBE_DEFER,
				     "i2c adapter not registered yet\n");

	cp->naddrs = of_property_count_u32_elems(dev->of_node, "r8q,addresses");
	if (cp->naddrs <= 0 || cp->naddrs > CAMPROBE_MAX_ADDRS) {
		ret = dev_err_probe(dev, -EINVAL, "bad r8q,addresses\n");
		goto err_put_adapter;
	}
	of_property_read_u32_array(dev->of_node, "r8q,addresses", cp->addrs,
				   cp->naddrs);

	/* Optional: an actuator or EEPROM has no MCLK of its own. */
	cp->mclk = devm_clk_get_optional(dev, NULL);
	if (IS_ERR(cp->mclk)) {
		ret = dev_err_probe(dev, PTR_ERR(cp->mclk), "no mclk\n");
		goto err_put_adapter;
	}

	cp->reset = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(cp->reset)) {
		ret = dev_err_probe(dev, PTR_ERR(cp->reset), "no reset gpio\n");
		goto err_put_adapter;
	}

	for (i = 0; i < ARRAY_SIZE(camprobe_supply_names); i++)
		cp->supplies[i].supply = camprobe_supply_names[i];

	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(cp->supplies),
				      cp->supplies);
	if (ret) {
		dev_err_probe(dev, ret, "no supplies\n");
		goto err_put_adapter;
	}

	ret = camprobe_power_on(cp);
	if (ret) {
		dev_err_probe(dev, ret, "power up failed\n");
		goto err_put_adapter;
	}

	dev_info(dev, "scanning %s\n", cp->adap->name);
	for (i = 0; i < cp->naddrs; i++)
		camprobe_scan_one(cp, cp->addrs[i]);
	dev_info(dev, "scan done\n");

	if (hold) {
		dev_info(dev, "holding power on (hold=1)\n");
		platform_set_drvdata(pdev, cp);
		return 0;
	}

	camprobe_power_off(cp);

	/*
	 * Deliberately fail the probe: this is a one-shot diagnostic and there
	 * is nothing to keep bound. -ENODEV also means a second insmod/rmmod
	 * cycle re-runs the scan instead of finding the device already claimed.
	 */
	ret = -ENODEV;

err_put_adapter:
	i2c_put_adapter(cp->adap);
	return ret;
}

static void camprobe_remove(struct platform_device *pdev)
{
	struct camprobe *cp = platform_get_drvdata(pdev);

	if (cp) {
		camprobe_power_off(cp);
		i2c_put_adapter(cp->adap);
	}
}

static const struct of_device_id camprobe_of_match[] = {
	{ .compatible = "r8q,cam-probe" },
	{ }
};
MODULE_DEVICE_TABLE(of, camprobe_of_match);

static struct platform_driver camprobe_driver = {
	.driver = {
		.name = "r8q-camprobe",
		.of_match_table = camprobe_of_match,
	},
	.probe = camprobe_probe,
	.remove = camprobe_remove,
};
module_platform_driver(camprobe_driver);

MODULE_DESCRIPTION("r8q camera sensor identification helper");
MODULE_LICENSE("GPL");
