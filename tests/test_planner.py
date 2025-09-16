from services.planner.planner import Planner


def test_planner_filters_blocked_targets():
    planner = Planner()
    plan = planner.from_llm(
        goal="Open settings",
        steps=[
            {"id": "1", "action": "click", "target": "settings"},
            {"id": "2", "action": "click", "target": "format drive"},
        ],
    )
    assert len(plan.steps) == 1
    assert plan.steps[0].target == "settings"
