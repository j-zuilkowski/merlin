import Foundation

/// Stable string constants for SwiftUI `.accessibilityIdentifier(_:)` modifiers.
/// Used by unit tests and `osascript` GUI automation to locate controls without
/// relying on display text (which can change with localisation).
///
/// Naming convention: `<screen>-<control>` in lowercase-dash format.
public enum AccessibilityID {

    // MARK: - Chat

    /// Main message input field.
    public static let chatInput = "chat-input"
    /// Send / submit button (or stop-generation button when generating).
    public static let chatSendButton = "chat-send-button"
    /// Explicit cancel / stop button (only visible while generating).
    public static let chatCancelButton = "chat-cancel-button"
    public static let chatAttachmentButton = "chat-attachment-button"
    public static let chatVoiceButton = "chat-voice-button"
    public static let chatStopButton = "chat-stop-button"
    public static let sideChatInput = "side-chat-input"
    public static let sideChatSendButton = "side-chat-send-button"
    public static let sideChatCancelButton = "side-chat-cancel-button"
    public static let sideChatAttachmentButton = "side-chat-attachment-button"
    public static let sideChatVoiceButton = "side-chat-voice-button"
    public static let chatToolbarActionPrefix = "chat-toolbar-action-"
    public static let chatResumeScrollButton = "chat-resume-scroll-button"
    public static let chatAtMentionPicker = "chat-at-mention-picker"
    public static let chatSkillsPicker = "chat-skills-picker"
    public static let chatDomainActivationSwitchButton = "chat-domain-activation-switch-button"
    public static let chatDomainActivationStayButton = "chat-domain-activation-stay-button"
    public static let chatDomainActivationCancelButton = "chat-domain-activation-cancel-button"

    // MARK: - Session sidebar

    /// The scrollable session list container.
    public static let sessionList = "session-list"
    /// "New Session" button at the bottom of the sidebar.
    public static let newSessionButton = "new-session-button"
    public static let sessionProjectHeaderPrefix = "session-project-header-"
    public static let sessionProjectNewButton = "session-project-new-button"
    public static let sessionProjectCloseButton = "session-project-close-button"
    public static let sessionArchivedTogglePrefix = "session-archived-toggle-"
    public static let slotStatusPanel = "slot-status-panel"
    public static let slotStatusRowPrefix = "slot-status-row-"

    // MARK: - Toolbar

    /// Settings gear button in the window toolbar.
    public static let settingsButton = "settings-button"

    // MARK: - Settings / provider picker

    /// The provider-selection picker control.
    public static let providerSelector = "provider-selector"
    public static let settingsProvidersRefreshButton = "settings-providers-refresh-button"
    public static let settingsProviderModelFieldPrefix = "settings-provider-model-field-"
    public static let settingsProviderMaxTokensFieldPrefix = "settings-provider-max-tokens-field-"
    public static let settingsProviderKeyButtonPrefix = "settings-provider-key-button-"
    public static let settingsProviderEnabledTogglePrefix = "settings-provider-enabled-toggle-"
    public static let settingsProviderUseButtonPrefix = "settings-provider-use-button-"
    public static let settingsProviderKeyField = "settings-provider-key-field"
    public static let settingsProviderKeyCancelButton = "settings-provider-key-cancel-button"
    public static let settingsProviderKeySaveButton = "settings-provider-key-save-button"
    public static let settingsProviderKeyClearButton = "settings-provider-key-clear-button"

    // MARK: - Settings / general

    public static let settingsGeneralKeepAwakeToggle = "settings-general-keep-awake-toggle"
    public static let settingsGeneralNotificationsToggle = "settings-general-notifications-toggle"
    public static let settingsGeneralPermissionModePicker = "settings-general-permission-mode-picker"
    public static let settingsGeneralMaxTokensStepper = "settings-general-max-tokens-stepper"
    public static let settingsGeneralAutoCompactToggle = "settings-general-auto-compact-toggle"
    public static let settingsGeneralMaxSubagentThreadsStepper = "settings-general-max-subagent-threads-stepper"
    public static let settingsGeneralMaxSubagentDepthStepper = "settings-general-max-subagent-depth-stepper"

    // MARK: - Settings / appearance

    public static let settingsAppearanceThemePicker = "settings-appearance-theme-picker"
    public static let settingsAppearanceFontSizeStepper = "settings-appearance-font-size-stepper"
    public static let settingsAppearanceFontNameField = "settings-appearance-font-name-field"
    public static let settingsAppearanceAccentColorField = "settings-appearance-accent-color-field"
    public static let settingsAppearanceDensityPicker = "settings-appearance-density-picker"

    // MARK: - Settings / roles and agents

    public static let settingsAgentProviderPicker = "settings-agent-provider-picker"
    public static let settingsAgentModelPicker = "settings-agent-model-picker"
    public static let settingsAgentCustomModelField = "settings-agent-custom-model-field"
    public static let settingsAgentReasoningToggle = "settings-agent-reasoning-toggle"
    public static let settingsAgentPromptCompressionToggle = "settings-agent-prompt-compression-toggle"
    public static let settingsAgentStandingInstructionsEditor = "settings-agent-standing-instructions-editor"
    public static let settingsRoleSlotsPickerPrefix = "settings-role-slots-picker-"
    public static let settingsRoleActiveDomainPicker = "settings-role-active-domain-picker"
    public static let settingsRoleVerifyCommandField = "settings-role-verify-command-field"
    public static let settingsRoleCheckCommandField = "settings-role-check-command-field"
    public static let settingsRoleProjectPathField = "settings-role-project-path-field"
    public static let settingsRoleMemoryEnabledToggle = "settings-role-memory-enabled-toggle"
    public static let settingsRoleRerankToggle = "settings-role-rerank-toggle"
    public static let settingsRoleChunkLimitStepper = "settings-role-chunk-limit-stepper"

    // MARK: - Settings / hooks

    public static let settingsHooksDisciplineToggle = "settings-hooks-discipline-toggle"
    public static let settingsHooksEnabledTogglePrefix = "settings-hooks-enabled-toggle-"
    public static let settingsHooksDeleteButtonPrefix = "settings-hooks-delete-button-"
    public static let settingsHooksEventPicker = "settings-hooks-event-picker"
    public static let settingsHooksCommandField = "settings-hooks-command-field"
    public static let settingsHooksCancelButton = "settings-hooks-cancel-button"
    public static let settingsHooksConfirmAddButton = "settings-hooks-confirm-add-button"
    public static let settingsHooksAddButton = "settings-hooks-add-button"

    // MARK: - Settings / memories, MCP, skills, search, permissions

    public static let settingsMemoriesEnabledToggle = "settings-memories-enabled-toggle"
    public static let settingsMemoriesIdlePicker = "settings-memories-idle-picker"
    public static let settingsMemoriesBackendPicker = "settings-memories-backend-picker"
    public static let settingsMCPDeleteButtonPrefix = "settings-mcp-delete-button-"
    public static let settingsMCPNameField = "settings-mcp-name-field"
    public static let settingsMCPCommandField = "settings-mcp-command-field"
    public static let settingsMCPArgsField = "settings-mcp-args-field"
    public static let settingsMCPCancelButton = "settings-mcp-cancel-button"
    public static let settingsMCPConfirmAddButton = "settings-mcp-confirm-add-button"
    public static let settingsMCPAddButton = "settings-mcp-add-button"
    public static let settingsSkillsEnabledTogglePrefix = "settings-skills-enabled-toggle-"
    public static let settingsSkillsOpenFolderButton = "settings-skills-open-folder-button"
    public static let settingsSearchAPIKeyField = "settings-search-api-key-field"
    public static let settingsSearchSaveButton = "settings-search-save-button"
    public static let settingsPermissionsRemoveButtonPrefix = "settings-permissions-remove-button-"

    // MARK: - Settings / connectors and advanced

    public static let settingsConnectorsGitHubTokenField = "settings-connectors-github-token-field"
    public static let settingsConnectorsSlackTokenField = "settings-connectors-slack-token-field"
    public static let settingsConnectorsLinearTokenField = "settings-connectors-linear-token-field"
    public static let settingsConnectorsXcalibreTokenField = "settings-connectors-xcalibre-token-field"
    public static let settingsConnectorsSaveButton = "settings-connectors-save-button"
    public static let settingsAdvancedShowConfigButton = "settings-advanced-show-config-button"
    public static let settingsAdvancedShowMemoriesButton = "settings-advanced-show-memories-button"
    public static let settingsAdvancedResetButton = "settings-advanced-reset-button"
    public static let settingsAdvancedConfirmResetButton = "settings-advanced-confirm-reset-button"
    public static let settingsAdvancedCancelResetButton = "settings-advanced-cancel-reset-button"

    // MARK: - Settings / LoRA and model controls

    public static let settingsLoRAEnableToggle = "settings-lora-enable-toggle"
    public static let settingsLoRAAutoTrainToggle = "settings-lora-auto-train-toggle"
    public static let settingsLoRAMinSamplesStepper = "settings-lora-min-samples-stepper"
    public static let settingsLoRABaseModelField = "settings-lora-base-model-field"
    public static let settingsLoRAAdapterPathField = "settings-lora-adapter-path-field"
    public static let settingsLoRAAdapterBrowseButton = "settings-lora-adapter-browse-button"
    public static let settingsLoRAAutoLoadToggle = "settings-lora-auto-load-toggle"
    public static let settingsLoRAServerURLField = "settings-lora-server-url-field"
    public static let settingsModelControlFieldPrefix = "settings-model-control-field-"
    public static let settingsModelControlFlashAttentionToggle = "settings-model-control-flash-attention-toggle"
    public static let settingsModelControlCacheKPicker = "settings-model-control-cache-k-picker"
    public static let settingsModelControlCacheVPicker = "settings-model-control-cache-v-picker"
    public static let settingsModelControlUseMmapToggle = "settings-model-control-use-mmap-toggle"
    public static let settingsModelControlUseMlockToggle = "settings-model-control-use-mlock-toggle"
    public static let settingsModelControlApplyReloadButton = "settings-model-control-apply-reload-button"
    public static let settingsModelControlRestartButton = "settings-model-control-restart-button"
    public static let settingsModelControlRestartDoneButton = "settings-model-control-restart-done-button"
    public static let settingsModelControlCopyCommandButton = "settings-model-control-copy-command-button"

    // MARK: - Workspace panels

    public static let terminalPaneInput = "terminal-pane-input"
    public static let terminalPaneRunButton = "terminal-pane-run-button"
    public static let terminalPaneStopButton = "terminal-pane-stop-button"
    public static let toolLog = "tool-log"
    public static let toolLogClearButton = "tool-log-clear-button"
    public static let diffPaneCommentFieldPrefix = "diff-pane-comment-field-"
    public static let diffPaneCommentSubmitButtonPrefix = "diff-pane-comment-submit-button-"
    public static let diffPaneCommentCancelButtonPrefix = "diff-pane-comment-cancel-button-"
    public static let diffPaneAcceptAllButton = "diff-pane-accept-all-button"
    public static let diffPaneRejectAllButton = "diff-pane-reject-all-button"
    public static let filePaneOpenButton = "file-pane-open-button"
    public static let filePaneCloseButton = "file-pane-close-button"
    public static let electronicsJobPanel = "electronics-job-panel"
    public static let cagMetricsPane = "cag-metrics-pane"
    public static let cagMetricsRefreshButton = "cag-metrics-refresh-button"
    public static let cagMetricsResetButton = "cag-metrics-reset-button"
    public static let cagMetricsCloseButton = "cag-metrics-close-button"
    public static let subagentSidebarRowPrefix = "subagent-sidebar-row-"
    public static let workerDiffFileList = "worker-diff-file-list"
    public static let workerDiffEmptyState = "worker-diff-empty-state"
    public static let workerDiffRejectAllButton = "worker-diff-reject-all-button"
    public static let workerDiffAcceptMergeButton = "worker-diff-accept-merge-button"
    public static let pendingAttentionCloseButton = "pending-attention-close-button"
    public static let pendingAttentionDismissButtonPrefix = "pending-attention-dismiss-button-"
    public static let pendingAttentionRationaleField = "pending-attention-rationale-field"
    public static let pendingAttentionCancelDismissButton = "pending-attention-cancel-dismiss-button"
    public static let pendingAttentionConfirmDismissButton = "pending-attention-confirm-dismiss-button"

    // MARK: - Memory browser and review

    public static let memoryBrowserSearchField = "memory-browser-search-field"
    public static let memoryBrowserSearchButton = "memory-browser-search-button"
    public static let memoryBrowserDeleteButtonPrefix = "memory-browser-delete-button-"
    public static let memoryReviewList = "memory-review-list"
    public static let memoryReviewRejectButton = "memory-review-reject-button"
    public static let memoryReviewApproveButton = "memory-review-approve-button"

    // MARK: - Dialogs and sheets

    public static let authArgumentButton = "auth-argument-button"
    public static let authAllowOnceButton = "auth-allow-once-button"
    public static let authAllowAlwaysButton = "auth-allow-always-button"
    public static let authDenyButton = "auth-deny-button"
    public static let projectPickerClearRecentsButton = "project-picker-clear-recents-button"
    public static let projectPickerCancelButton = "project-picker-cancel-button"
    public static let projectPickerOpenFolderButton = "project-picker-open-folder-button"
    public static let projectPickerOpenButton = "project-picker-open-button"
    public static let firstLaunchProviderPicker = "first-launch-provider-picker"
    public static let firstLaunchAPIKeyField = "first-launch-api-key-field"
    public static let firstLaunchSkipButton = "first-launch-skip-button"
    public static let firstLaunchContinueButton = "first-launch-continue-button"
    public static let btwCloseButton = "btw-close-button"
    public static let btwQuestionField = "btw-question-field"
    public static let btwSubmitButton = "btw-submit-button"
    public static let schedulerAddButton = "scheduler-add-button"
    public static let schedulerNameField = "scheduler-name-field"
    public static let schedulerTimeField = "scheduler-time-field"
    public static let schedulerProjectPathField = "scheduler-project-path-field"
    public static let schedulerPromptField = "scheduler-prompt-field"
    public static let schedulerConfirmAddButton = "scheduler-confirm-add-button"
    public static let schedulerCancelButton = "scheduler-cancel-button"
    public static let calibrationCancelButton = "calibration-cancel-button"
    public static let calibrationProviderPicker = "calibration-provider-picker"
    public static let calibrationStartButton = "calibration-start-button"
    public static let calibrationDoneButton = "calibration-done-button"
    public static let calibrationApplyAllButton = "calibration-apply-all-button"

    // MARK: - Workspace pane toggle buttons

    public static let workspaceToggleDiffButton = "workspace-toggle-diff-button"
    public static let workspaceToggleFileButton = "workspace-toggle-file-button"
    public static let workspaceToggleTerminalButton = "workspace-toggle-terminal-button"
    public static let workspaceTogglePreviewButton = "workspace-toggle-preview-button"
    public static let workspaceToggleSideChatButton = "workspace-toggle-side-chat-button"
    public static let workspaceToggleMemoriesButton = "workspace-toggle-memories-button"
    public static let workspaceToggleCAGMetricsButton = "workspace-toggle-cag-metrics-button"
    public static let workspaceToggleElectronicsJobsButton = "workspace-toggle-electronics-jobs-button"
    public static let screenPreviewToggleButton = "screen-preview-toggle-button"
    public static let previewPaneCloseButton = "preview-pane-close-button"
    public static let toolRequirementInstallButton = "tool-requirement-install-button"
    public static let toolRequirementCancelButton = "tool-requirement-cancel-button"
    public static let toolRequirementDoneButton = "tool-requirement-done-button"
    public static let performanceAdvisoryApplyButtonPrefix = "performance-advisory-apply-button-"
}
