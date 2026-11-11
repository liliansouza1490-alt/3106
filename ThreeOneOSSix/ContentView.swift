import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.externalGameSelection) private var selectedGame
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(TabBarSelection.storageKey)
    private var tabBarSelectionRaw = TabBarSelection.defaultRaw
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = true
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: developerModeEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onChange(of: tabBarSelectionRaw) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            if tabBarSelectionRaw == TabBarSelection.legacyDefaultRaw
                || tabBarSelectionRaw == TabBarSelection.previousDefaultRaw
                || tabBarSelectionRaw == TabBarSelection.lastDefaultRaw {
                tabBarSelectionRaw = TabBarSelection.defaultRaw
            }
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
        .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
    }

    private var compactLayout: some View {
        sectionContent(selectedVisibleSection)
            .id(selectedVisibleSection.rawValue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SimpleBottomBar(
                    sections: featureVisibility.visibleSections,
                    selectedSection: selectedVisibleSection,
                    language: language
                ) { section in
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        tabNavigation.select(section.rawValue)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle(selectedGame.title)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
                .background(AppTheme.pageBackground.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .cleaner:
            CleanerView(onOpenSettings: openSettings)
        case .wallpapers:
            WallpaperLabView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(
            selectedSections: TabBarSelection.sections(from: tabBarSelectionRaw),
            wallpapersSupported: WallpaperFeatureSupportPolicy.isSupported(
                major: AppInfo.versionTuple.major
            ),
            developerModeEnabled: developerModeActive
        )
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .home
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct SimpleBottomBar: View {
    let sections: [AppSection]
    let selectedSection: AppSection
    let language: AppLanguage
    let onSelect: (AppSection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sections) { section in
                let isSelected = section == selectedSection
                Button {
                    onSelect(section)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                            .frame(height: 19)
                        Text(language.text(section.titleKey))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 3)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.28))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}
