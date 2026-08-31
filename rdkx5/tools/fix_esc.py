import pathlib

p = pathlib.Path("rdkx5/pixhawk_link.py")
content = p.read_text(encoding="utf-8")

old_block = '''    def initialize_escs(self) -> None:
        """Send correct neutral PWM to every output channel.

        This is the key fix for ESC "no signal" / "throttle not at zero" alarms:
            * MAIN1-8 get 1500 (bidirectional thruster neutral)
            * AUX5/AUX6 get 1000 (one-way suction ESC stopped)
            * Remaining AUX channels get 1500 (servo neutral)

        Called automatically after arming; can also be invoked manually via
        the ``init_escs`` command to silence ESCs without arming.
        """
        if self.simulation:
            return
        if self.master is None or self.mavutil is None:
            LOGGER.warning("[RDK X5] initialize_escs: Pixhawk not connected")
            return
        neutral = int(self.config.get("neutral_pwm", 1500))
        suction_neutral = self._suction_neutral_pwm()
        suction_channels = [int(c) for c in self.config.get("suction_channels", [])]
        for channel in range(1, 17):
            pwm = suction_neutral if channel in suction_channels else neutral
            try:
                self.set_pwm(channel, pwm)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] init channel %d failed: %s", channel, exc)
        LOGGER.info(
            "[RDK X5] ESCs initialized: MAIN1-8=%d, suction(AUX%s)=%d",
            neutral,
            suction_channels,
            suction_neutral,
        )'''

new_block = '''    def initialize_escs(self) -> None:
        """Send correct neutral PWM to AUX output channels only.

        CRITICAL: Do NOT send DO_SET_SERVO to MAIN1-8. Those channels are
        controlled by the ArduSub motor mixer (SERVO1-8_FUNCTION=Motor1-8).
        Sending DO_SET_SERVO to a Motor channel causes ServoRelayEvent
        Channel already in use error and prevents arming.

        MAIN1-8 neutral is handled by the mixer via MANUAL_CONTROL.
        Only AUX channels (9-16) need explicit DO_SET_SERVO.
        """
        if self.simulation:
            return
        if self.master is None or self.mavutil is None:
            LOGGER.warning("[RDK X5] initialize_escs: Pixhawk not connected")
            return
        neutral = int(self.config.get("neutral_pwm", 1500))
        suction_neutral = self._suction_neutral_pwm()
        suction_channels = [int(c) for c in self.config.get("suction_channels", [])]
        for channel in range(9, 17):
            pwm = suction_neutral if channel in suction_channels else neutral
            try:
                self.set_pwm(channel, pwm)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] init AUX channel %d failed: %s", channel, exc)
        LOGGER.info(
            "[RDK X5] AUX initialized: suction=%d servo=%d (MAIN1-8 left to mixer)",
            suction_neutral,
            neutral,
        )'''

if old_block in content:
    content = content.replace(old_block, new_block)
    p.write_text(content, encoding="utf-8")
    print("FIXED: initialize_escs now only targets AUX channels")
else:
    print("ERROR: old block not found")
