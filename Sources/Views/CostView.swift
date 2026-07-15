import SwiftUI

/// Cost data row. Mirrors `UsageView`'s data-row shape so swipe transitions
/// between them don't reflow the panel. Chrome (provider titles, footer
/// chip + page dots + sync status) lives in `PanelHeader` / `PanelFooter`.
///
/// Branches on `(claudeOn, codexOn)` from `ProviderVisibilityStore`:
///   - both on:  two per-model cost breakdowns with a hairline divider.
///   - one on:   the visible provider's breakdown expands across the row.
///   - both off: a centered `BothHiddenPlaceholder`.
struct CostView: View {
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        let claudeOn = visibility.claudeVisible
        let codexOn = visibility.codexVisible

        HStack(spacing: 0) {
            switch (claudeOn, codexOn) {
            case (true, true):
                CostModelBreakdown(provider: .claude)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                hairline
                CostModelBreakdown(provider: .codex)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
            case (true, false):
                singleProviderDashboard(.claude)
                    .transition(breakdownTransition)
            case (false, true):
                singleProviderDashboard(.codex)
                    .transition(breakdownTransition)
            case (false, false):
                BothHiddenPlaceholder()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }


    private func singleProviderDashboard(_ provider: AlertEngine.Provider) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CostModelBreakdown(provider: provider)
                .frame(width: 396, alignment: .topLeading)
            CostWeeklyTrendPanel(provider: provider)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
    }

    /// Mirror of `UsageView.breakdownTransition` — kept inline (not extracted
    /// to a shared helper) because it's two views and the transition's
    /// emotional purpose is "this half has been repurposed for the
    /// breakdown", which is a per-page editorial choice.
    private var breakdownTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, .white.opacity(0.06), .clear],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}
