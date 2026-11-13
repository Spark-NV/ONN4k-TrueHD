// SPDX-License-Identifier: GPL-2.0
/*
 * The HDMI multichannel link (TDM-B) on this box goes through the T9015 codec
 * DAI, which only advertises 8-96 kHz. TrueHD/MAT needs 192 kHz, so this bumps
 * the rate mask to 8-192 kHz in the loaded driver. Only in memory: rmmod or a
 * reboot puts the stock value back.
 *
 * Pass data_base = /sys/module/amlogic_snd_codec_t9015/sections/.data. The
 * playback and capture snd_soc_pcm_stream structs live at fixed offsets in
 * there. We check they look exactly like the stock build before writing.
 */
#include <linux/module.h>
#include <linux/moduleparam.h>

#define OLD_RATES	0x7fe		/* SNDRV_PCM_RATE_8000_96000 */
#define NEW_RATES	0x1ffe		/* SNDRV_PCM_RATE_8000_192000 */
#define STOCK_FORMATS	0x1000000445ULL

#define PLAY_OFF	0x140		/* &playback.formats */
#define CAP_OFF		0x170		/* &capture.formats */

static unsigned long data_base;
module_param(data_base, ulong, 0444);

static u32 *rates_play, *rates_cap;

static bool stream_ok(unsigned long p, u32 ch_max)
{
	return READ_ONCE(*(u64 *)p) == STOCK_FORMATS &&
	       READ_ONCE(*(u32 *)(p + 8)) == OLD_RATES &&
	       READ_ONCE(*(u32 *)(p + 20)) == 2 &&
	       READ_ONCE(*(u32 *)(p + 24)) == ch_max;
}

static int __init t9015rate_init(void)
{
	if (!data_base)
		return -EINVAL;
	if (!stream_ok(data_base + PLAY_OFF, 8) ||
	    !stream_ok(data_base + CAP_OFF, 16)) {
		pr_err("t9015rate: layout at %lx does not match, not patching\n",
		       data_base);
		return -EINVAL;
	}
	rates_play = (u32 *)(data_base + PLAY_OFF + 8);
	rates_cap = (u32 *)(data_base + CAP_OFF + 8);
	WRITE_ONCE(*rates_play, NEW_RATES);
	WRITE_ONCE(*rates_cap, NEW_RATES);
	pr_info("t9015rate: rates %x -> %x\n", OLD_RATES, NEW_RATES);
	return 0;
}

static void __exit t9015rate_exit(void)
{
	WRITE_ONCE(*rates_play, OLD_RATES);
	WRITE_ONCE(*rates_cap, OLD_RATES);
	pr_info("t9015rate: rates restored to %x\n", OLD_RATES);
}

module_init(t9015rate_init);
module_exit(t9015rate_exit);
MODULE_DESCRIPTION("Lift the T9015 codec DAI 96 kHz cap so HDMI can carry HBR audio");
MODULE_LICENSE("GPL");
