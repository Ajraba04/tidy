extension CleanCatalog {
    /// Section 3 (DerivedData etc., safe) and section 4 (simulator devices,
    /// deep) of the shell script. Populated in Phases 4 and 6.
    static var xcodeAndSimulators: CleanCategory {
        CleanCategory(id: "xcode-simulators", title: "Xcode & Simulators", items: [])
    }
}
