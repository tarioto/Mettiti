import SwiftUI

/// Shows `plan` for an entry with a plan, and the empty or "Open Mettiti to update" state otherwise.
struct PlanStateView<Plan: View>: View {
    let state: WidgetPlanTimeline.State
    @ViewBuilder let plan: (PlanSnapshot) -> Plan

    var body: some View {
        switch state {
        case .plan(let snapshot):
            plan(snapshot)
        case .empty:
            EmptyPlanView()
        case .needsUpdate:
            EmptyPlanView.needsUpdate
        }
    }
}
