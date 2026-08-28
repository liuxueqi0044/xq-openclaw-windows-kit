@{
    Severity = @('Error','Warning')
    IncludeRules = @('*')
    ExcludeRules = @(
        'PSUseApprovedVerbs'
        'PSUseSingularNouns'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
