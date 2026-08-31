import pathlib

p = pathlib.Path("rdkx5/pixhawk_link.py")
lines = p.read_text(encoding="utf-8").split("\n")

# Find the keepalive method line and insert the helper before it
insert_before = None
keepalive_start = None
keepalive_end = None
for i, line in enumerate(lines):
    if "def _send_rc_override_keepalive" in line:
        insert_before = i
        keepalive_start = i
    if keepalive_start and i > keepalive_start and line.strip() == "" and i > keepalive_start + 2:
        # Check if next non-empty line is at same or lower indent (end of method)
        for j in range(i+1, min(i+3, len(lines))):
            if lines[j].strip() and not lines[j].startswith("        "):
                keepalive_end = i
                break
        if keepalive_end:
            break

# Simpler approach: find lines 653-670 (0-indexed 652-669) and replace
# Also insert the helper method before
helper = """    def _rc_channels_override(self, channels: list[int]) -> None:
        \"\"\"Send RC_CHANNELS_OVERRIDE, handling both old and new pymavlink.\"\"\"
        if self.master is None or self.mavutil is None:
            return
        ch = list(channels) + [65535] * max(0, 16 - len(channels))
        try:
            self.master.mav.rc_channels_override_send(
                self.target_system, self.target_component,
                ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
                ch[8], ch[9], ch[10], ch[11], ch[12], ch[13], ch[14], ch[15],
            )
        except TypeError:
            try:
                self.master.mav.rc_channels_override_send(
                    self.target_system, self.target_component,
                    ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
                )
            except Exception as exc:
                LOGGER.warning("[RDK X5] rc_override 8ch failed: %s", exc)
        except Exception as exc:
            LOGGER.warning("[RDK X5] rc_override failed: %s", exc)

    def _send_rc_override_keepalive(self) -> None:
        \"\"\"Send all-1500 RC_CHANNELS_OVERRIDE to reset pilot input failsafe.\"\"\"
        self._rc_channels_override([1500] * 16)"""

# Find and replace the keepalive method
content = "\n".join(lines)

# Find the old keepalive block
old_start = "    def _send_rc_override_keepalive(self) -> None:"
idx = content.find(old_start)
if idx < 0:
    print("ERROR: keepalive not found")
    exit(1)

# Find the end of the keepalive method (next def at 4-space indent or class boundary)
rest = content[idx:]
lines_rest = rest.split("\n")
end_offset = 0
for i in range(1, len(lines_rest)):
    line = lines_rest[i]
    if line and not line.startswith(" ") and not line.startswith("\t"):
        end_offset = sum(len(l)+1 for l in lines_rest[:i])
        break
    if line.startswith("    def ") and i > 1:
        end_offset = sum(len(l)+1 for l in lines_rest[:i])
        break
    if line.startswith("    # ") and i > 1:
        end_offset = sum(len(l)+1 for l in lines_rest[:i])
        break

if end_offset == 0:
    # Take a generous chunk
    end_offset = sum(len(l)+1 for l in lines_rest[:20])

old_block = content[idx:idx+end_offset]
new_content = content[:idx] + helper + "\n\n" + content[idx+end_offset:]

p.write_text(new_content, encoding="utf-8")
print("Added _rc_channels_override helper and fixed keepalive")
