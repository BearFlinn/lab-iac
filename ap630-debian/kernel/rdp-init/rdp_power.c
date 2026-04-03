// SPDX-License-Identifier: GPL-2.0
/*
 * BCM4908 RDP/FPM power-on driver.
 * Matches DTS nodes with compatible "brcm,bcm4908-rdp-power" and holds
 * their power domains active via pm_runtime. This keeps the RDP block
 * (0x82200000) and FPM block (0x82c00000) powered on and accessible.
 */

#include <linux/module.h>
#include <linux/io.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>

static int rdp_power_probe(struct platform_device *pdev)
{
	pm_runtime_enable(&pdev->dev);
	pm_runtime_resume_and_get(&pdev->dev);
	dev_info(&pdev->dev, "power domain held active\n");
	return 0;
}

static void rdp_power_remove(struct platform_device *pdev)
{
	pm_runtime_put(&pdev->dev);
	pm_runtime_disable(&pdev->dev);
}

static const struct of_device_id rdp_power_of_match[] = {
	{ .compatible = "brcm,bcm4908-rdp-power" },
	{ },
};
MODULE_DEVICE_TABLE(of, rdp_power_of_match);

static struct platform_driver rdp_power_driver = {
	.driver = {
		.name = "bcm4908-rdp-power",
		.of_match_table = rdp_power_of_match,
	},
	.probe = rdp_power_probe,
	.remove = rdp_power_remove,
};
module_platform_driver(rdp_power_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("BCM4908 RDP/FPM power domain holder");
