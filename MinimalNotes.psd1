@{
    RootModule = 'MinimalNotes.psm1'
    ModuleVersion = '0.1.0'
    GUID = '0f3ae5ec-a3bc-4cd3-b4d6-d24499b7ced6'
    Author = 'Spinchange'
    CompanyName = 'Spinchange'
    Copyright = '(c) Spinchange. All rights reserved.'
    Description = 'A lightweight, local-first, Obsidian-inspired notes module and CLI for PowerShell 7.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Invoke-MinimalNotesCli',
        'Get-MinimalNotesVaultPath'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
