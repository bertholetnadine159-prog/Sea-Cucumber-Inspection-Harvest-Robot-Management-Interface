import pathlib

p = pathlib.Path("rdkx5/pixhawk_link.py")
content = p.read_text(encoding="utf-8")

# Add a helper method for rc_channels_override that handles both old/new pymavlink
# Insert it right before _send_rc_override_keepalive
old_keepalive = """    def _send_rc_override_keepalive(self) -> None:
        \"\"\"Send all-1500 RC_CHANNELS_OVERRIDE to reset pilot input failsafe.

        Does not affect MANUAL_CONTROL control; all channels at 1500 neutral.
        Only purpose: keep FS_PILOT_INPUT timer from expiring.
        \"\"\"
        if self.master is None or self.mavutil is None:
            return
        try:
            self.master.mav.rc_channels_override_send(
                self.target_system,
                self.target_component,
                1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500,
                1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500,
            )
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] rc_override keepalive failed: %s", exc)"""

new_keepalive = """    def _rc_channels_override(self, channels: list[int]) -> None:
        \"\"\"Send RC_CHANNELS_OVERRIDE, handling both old (8-ch) and new (16-ch) pymavlink.\"\"\"
        if self.master is None or self.mavutil is None:
            return
        # Pad to at least 8 channels
        ch = list(channels) + [65535] * max(0, 8 - len(channels))
        try:
            # Try 16-channel version first (newer pymavlink)
            self.master.mav.rc_channels_override_send(
                self.target_system, self.target_component,
                ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
                ch[8], ch[9], ch[10], ch[11], ch[12], ch[13], ch[14], ch[15],
            )
        except TypeError:
            # Fall back to 8-channel version (older pymavlink on RDK X5)
            try:
                self.master.mav.rc_channels_override_send(
                    self.target_system, self.target_component,
                    ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
                )
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] rc_override 8ch failed: %s", exc)
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] rc_override failed: %s", exc)

    def _send_rc_override_keepalive(self) -> None:
        \"\"\"Send all-1500 RC_CHANNELS_OVERRIDE to reset pilot input failsafe.

        Does not affect MANUAL_CONTROL control; all channels at 1500 neutral.
        Only purpose: keep FS_PILOT_INPUT timer from expiring.
        \"\"\"
        self._rc_channels_override([1500] * 16)"""

if old_keepalive in content:
    content = content.replace(old_keepalive, new_keepalive)
    print("Fixed _send_rc_override_keepalive with helper")
else:
    print("ERROR: keepalive block not found")

# Now fix _send_rc_override to use the helper
old_override = """        try:
            self.master.mav.rc_channels_override_send(
                self.target_system,
                self.target_component,
                channels[0],
                channels[1],
                channels[2],
                channels[3],
                channels[4],
                channels[5],
                channels[6],
                channels[7],
                channels[8],
                channels[9],
                channels[10],
                channels[11],
                channels[12],
                channels[13],
                channels[14],
                channels[15],
            )
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] rc_channels_override_send failed: %s", exc)"""

new_override = """        self._rc_channels_override(channels)"""

if old_override in content:
    content = content.replace(old_override, new_override)
    print("Fixed _send_rc_override to use helper")
else:
    print("ERROR: override block not found")

p.write_text(content, encoding="utf-8")
print("Done")
