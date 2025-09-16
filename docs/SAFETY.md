# Safety Guidelines

1. **Human-in-the-loop**: all irreversible actions require confirmation via the gateway UI.
2. **Rate limiting**: HID service enforces keypress/mouse limits to prevent runaway loops.
3. **Logging**: every action is logged with timestamps and plan references for auditing.
4. **Network isolation**: default deployment avoids outbound internet access from the LLM and planner containers.
5. **Policy enforcement**: planner checks `configs/policy.yml` and denies commands that match blocked patterns.
