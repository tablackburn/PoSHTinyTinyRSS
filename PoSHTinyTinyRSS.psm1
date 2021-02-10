<#
TODO:
implement api calls: setArticleLabel, shareToPublished, subscribeToFeed, unsubscribeFeed, unsubscribeFeed, getFeedTree
#>

#region load module variables
Write-Verbose 'Creating module variables'
$TinyTinyRSSSession = [ordered]@{
    Uri         = $null
    Sid         = $null
    ContentType = 'application/json'
    Method      = 'Post'
    ApiLevel    = $null
}
New-Variable -Name 'TinyTinyRSSSession' -Value $TinyTinyRSSSession -Description 'Session details about the Tiny Tiny RSS server connection' -Scope Script -Force

$specialFeedIds = @{
    Starred     = -1
    Published   = -2
    Fresh       = -3
    AllArticles = -4
    Archived    = 0
}
New-Variable -Name 'SpecialFeedIds' -Value $specialFeedIds -Description 'Special/virtual feed IDs' -Scope Script -Force
#endregion load module variables

function Connect-TinyTinyRSS {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true,
            HelpMessage = 'Enter the URL used to access the Tiny Tiny RSS server (such as http://example.com/tt-rss)')]
        [System.Uri]
        $Uri,
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )

    # build JSON to pass to the -Body parameter such as: {"op":"login","user":"user","password":"xxx"}
    $body = @{
        op       = 'login'
        user     = $Credential.UserName
        password = $Credential.GetNetworkCredential().Password
    } | ConvertTo-Json -Compress

    # build the parameters for the REST cmdlet
    $parameters = @{
        Uri         = $Uri.AbsoluteUri + 'api/' -as [System.Uri]
        ContentType = $TinyTinyRSSSession.ContentType
        Method      = $TinyTinyRSSSession.Method
        Body        = $body
    }

    $session = Invoke-RestMethod @parameters
    $sessionId = $session.content.session_id
    if ($sessionId) {
        $TinyTinyRSSSession.Uri = $parameters.Uri
        $TinyTinyRSSSession.Sid = $sessionId
        $TinyTinyRSSSession.ApiLevel = (Get-ApiLevel).level
    }
    else {
        throw 'Failed to connect: ' -f $session
    }
}

function Get-TinyTinyRSSSession {
    [CmdletBinding()]
    param ()

    $TinyTinyRSSSession
}

function Invoke-TinyTinyRSSAPI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $Method,
        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [hashtable]
        $Parameters
    )

    $body = @{
        sid = $TinyTinyRSSSession.Sid
        op  = $Method
    }
    if ($PSBoundParameters.ContainsKey('Parameters')) {
        $body += $Parameters
    }
    $requestParameters = @{
        Uri         = $TinyTinyRSSSession.Uri
        ContentType = $TinyTinyRSSSession.ContentType
        Method      = $TinyTinyRSSSession.Method
        Body        = $body | ConvertTo-Json -Compress
    }
    $requestParameters | Out-String | Write-Debug

    $result = Invoke-RestMethod @requestParameters
    $result.content
}

function Get-ApiLevel {
    [CmdletBinding()]
    param ()

    Invoke-TinyTinyRSSAPI -Method 'getApiLevel'
}

function Get-Unread {
    [CmdletBinding()]
    param ()

    Invoke-TinyTinyRSSAPI -Method 'getUnread'
}

function Get-Counters {
    [CmdletBinding()]
    param (
        [switch]
        $Feeds,
        [switch]
        $Labels,
        [switch]
        $Categories,
        [switch]
        $Tags
    )

    $outputMode = ''
    if ($PSBoundParameters.ContainsKey('Feeds')) {
        $outputMode += 'f'
    }
    if ($PSBoundParameters.ContainsKey('Labels')) {
        $outputMode += 'l'
    }
    if ($PSBoundParameters.ContainsKey('Categories')) {
        $outputMode += 'c'
    }
    if ($PSBoundParameters.ContainsKey('Tags')) {
        $outputMode += 't'
    }

    Invoke-TinyTinyRSSAPI -Method 'getCounters' -Parameters @{ output_mode = $outputMode }
}

function Get-Feed {
    [CmdletBinding()]
    param (
        [ArgumentCompleter( {
                (Get-Feed).cat_id
            }
        )]
        [int]
        $CategoryId,
        [switch]
        $UnreadOnly,
        [int]
        $Limit,
        [int]
        $Offset,
        [switch]
        $IncludeNested
    )

    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('CategoryId')) {
        $parameters['cat_id'] = $CategoryId
    }
    if ($PSBoundParameters.ContainsKey('UnreadOnly')) {
        $parameters['unread_only'] = $true
    }
    if ($PSBoundParameters.ContainsKey('Limit')) {
        $parameters['limit'] = $Limit
    }
    if ($PSBoundParameters.ContainsKey('Offset')) {
        $parameters['offset'] = $Offset
    }
    if ($PSBoundParameters.ContainsKey('IncludeNested')) {
        $parameters['include_nested'] = $true
    }

    $result = Invoke-TinyTinyRSSAPI -Method 'getFeeds' -Parameters $parameters
    $result | Select-Object -Property *, @{Name = 'last_updated'; Expression = { (Get-Date -Date '1970-01-01 00:00:00Z').AddSeconds($_.last_updated) } } -ExcludeProperty last_updated
}

function Get-Category {
    [CmdletBinding()]
    param (
        [switch]
        $UnreadOnly,
        [switch]
        $EnableNested,
        [switch]
        $IncludeEmpty
    )

    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('UnreadOnly')) {
        $parameters['unread_only'] = $true
    }
    if ($PSBoundParameters.ContainsKey('EnableNested')) {
        $parameters['enable_nested'] = $true
    }
    if ($PSBoundParameters.ContainsKey('IncludeEmpty')) {
        $parameters['include_empty'] = $true
    }

    Invoke-TinyTinyRSSAPI -Method 'getCategories' -Parameters $parameters
}

function Get-Headline {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'FeedId')]
        [ArgumentCompleter( {
                (Get-Feed).id
            })]
        [int]
        $FeedId,
        [Parameter(Mandatory = $false, ParameterSetName = 'CategoryId')]
        [ArgumentCompleter( {
                (Get-Feed).cat_id
            })]
        [int]
        $CategoryId,
        [int]
        $Limit,
        [int]
        $Skip,
        [switch]
        $ShowExcerpt,
        [switch]
        $ShowContent,
        [ValidateSet('all_articles', 'unread', 'adaptive', 'marked', 'updated')]
        [string]
        $ViewMode = 'adaptive',
        [switch]
        $IncludeAttachments,
        [int]
        $SinceId,
        [switch]
        $IncludeNested,
        [ValidateSet('date_reverse', 'feed_dates')]
        [string]
        $OrderBy,
        [switch]
        $SkipSanitize,
        [switch]
        $ForceUpdate,
        [switch]
        $HasSandbox,
        [switch]
        $IncludeHeader,
        [Parameter(Mandatory = $true, ParameterSetName = 'Feed')]
        [ArgumentCompleter( {
                (Get-Feed).title
            })]
        [string]
        $Feed,
        [string]
        $Search,
        [ValidateSet('all_feeds', 'this_feed', 'this_cat')]
        [string]
        $SearchMode
    )

    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('FeedId')) {
        $parameters['feed_id'] = $FeedId
    }
    elseif ($PSBoundParameters.ContainsKey('CategoryId')) {
        $parameters['feed_id'] = $CategoryId
        $parameters['is_cat'] = $true
    }
    elseif ($PSBoundParameters.ContainsKey('Feed')) {
        $parameters['feed_id'] = (Get-Feed | Where-Object title -EQ $Feed).id
    }
    if ($PSBoundParameters.ContainsKey('Limit')) {
        $parameters['limit'] = $Limit
    }
    if ($PSBoundParameters.ContainsKey('Skip')) {
        $parameters['skip'] = $Skip
    }
    if ($PSBoundParameters.ContainsKey('ShowExcerpt')) {
        $parameters['show_excerpt'] = $true
    }
    if ($PSBoundParameters.ContainsKey('ShowContent')) {
        $parameters['show_content'] = $true
    }
    if ($PSBoundParameters.ContainsKey('ViewMode')) {
        $parameters['view_mode'] = $ViewMode
    }
    if ($PSBoundParameters.ContainsKey('IncludeAttachments')) {
        $parameters['include_attachments'] = $true
    }
    if ($PSBoundParameters.ContainsKey('SinceId')) {
        $parameters['since_id'] = $SinceId
    }
    if ($PSBoundParameters.ContainsKey('IncludeNested')) {
        $parameters['include_nested'] = $true
    }
    if ($PSBoundParameters.ContainsKey('OrderBy')) {
        $parameters['order_by'] = $OrderBy
    }
    if ($PSBoundParameters.ContainsKey('SkipSanitize')) {
        $parameters['sanitize'] = $false
    }
    if ($PSBoundParameters.ContainsKey('ForceUpdate')) {
        $parameters['force_update'] = $true
    }
    if ($PSBoundParameters.ContainsKey('HasSandbox')) {
        $parameters['has_sandbox'] = $true
    }
    if ($PSBoundParameters.ContainsKey('IncludeHeader')) {
        $parameters['include_header'] = $true
    }
    if ($PSBoundParameters.ContainsKey('Search')) {
        $parameters['search'] = $Search
    }
    if ($PSBoundParameters.ContainsKey('SearchMode')) {
        $parameters['search_mode'] = $SearchMode # TODO: convert this into a dynamic parameter
    }

    $result = Invoke-TinyTinyRSSAPI -Method 'getHeadlines' -Parameters $parameters
    $result | Select-Object -Property *, @{Name = 'updated'; Expression = { (Get-Date -Date '1970-01-01 00:00:00Z').AddSeconds($_.updated) } } -ExcludeProperty updated
}

function Set-Article {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [int[]]
        $ArticleId,
        [Parameter(Mandatory = $false, ParameterSetName = 'Mode')]
        [ValidateSet('SetToFalse', 'SetToTrue', 'Toggle')]
        [string]
        $Mode,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Starred', 'Published', 'Unread', 'ArticleNote')]
        [string]
        $Field
    )

    DynamicParam {
        # create a Data parameter if ArticleNote is specified for the Field parameter
        if ($Field -eq 'ArticleNote') {
            # create a new ParameterAttribute object and specify the parameter attributes
            $dataAttribute = New-Object System.Management.Automation.ParameterAttribute
            $dataAttribute.ParameterSetName = 'ArticleNote'
            $dataAttribute.Mandatory = $true

            # create a collection object and add the previously created attributes
            $attributeCollection = New-Object Collections.ObjectModel.Collection[System.Attribute]
            $attributeCollection.Add($dataAttribute)

            # create the parameter
            $dataParameter = New-Object System.Management.Automation.RuntimeDefinedParameter('Data', [string], $attributeCollection)

            # expose the parameter
            $parameterDictionary = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary
            $parameterDictionary.Add("Data", $dataParameter)
            $parameterDictionary
        }
    }

    process {
        $parameters = @{}
        if ($PSBoundParameters.ContainsKey('ArticleId')) {
            $parameters['article_ids'] = $ArticleId -join ','
        }
        if ($PSBoundParameters.ContainsKey('Mode')) {
            switch ($Mode) {
                'SetToFalse' { $modeInteger = 0; break }
                'SetToTrue' { $modeInteger = 1; break }
                'Toggle' { $modeInteger = 2; break }
            }
            $parameters['mode'] = $modeInteger
        }
        if ($PSBoundParameters.ContainsKey('Field')) {
            switch ($Field) {
                'Starred' { $fieldInteger = 0; break }
                'Published' { $fieldInteger = 1; break }
                'Unread' { $fieldInteger = 1; break }
                'ArticleNote' { $fieldInteger = 2; break }
            }
            $parameters['field'] = $fieldInteger
        }
        if ($PSBoundParameters.ContainsKey('Data')) {
            $parameters['data'] = $PSBoundParameters.Data
        }

        Invoke-TinyTinyRSSAPI -Method 'updateArticle' -Parameters $parameters
    }
}

function Get-Article {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [int]
        $ArticleId
    )

    Invoke-TinyTinyRSSAPI -Method 'getArticle' -Parameters @{ article_id = $ArticleId }
}

function Get-Config {
    [CmdletBinding()]
    param ()

    Invoke-TinyTinyRSSAPI -Method 'getConfig'
}

function Update-Feed {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ArgumentCompleter( {
                (Get-Feed).id
            })]
        [int]
        $FeedId
    )

    Invoke-TinyTinyRSSAPI -Method 'updateFeed' -Parameters @{ feed_id = $FeedId }
}

function Get-Preference {
    [CmdletBinding()]
    param (
        [string]
        $PrefName
    )

    Invoke-TinyTinyRSSAPI -Method 'getPref' -Parameters @{ pref_name = $PrefName }
}

function Set-Read {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ParameterSetName = 'FeedId')]
        [ArgumentCompleter( {
                (Get-Feed).id
            })]
        [int]
        $FeedId,
        [Parameter(Mandatory = $false, ParameterSetName = 'CategoryId')]
        [ArgumentCompleter( {
                (Get-Feed).cat_id
            })]
        [int]
        $CategoryId,
        [ValidateSet('all', '1day', '1week', '2week')]
        [string]
        $Mode
    )

    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('FeedId')) {
        $parameters['feed_id'] = $FeedId
    }
    elseif ($PSBoundParameters.ContainsKey('CategoryId')) {
        $parameters['feed_id'] = $CategoryId
        $parameters['is_cat'] = $true
    }
    if ($PSBoundParameters.ContainsKey('Mode')) {
        $parameters['mode'] = $Mode
    }

    Invoke-TinyTinyRSSAPI -Method 'catchupFeed' -Parameters $parameters
}

function Get-Label {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [int]
        $ArticleId
    )

    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('ArticleId')) {
        $parameters['article_id'] = $ArticleId
    }

    Invoke-TinyTinyRSSAPI -Method 'getLabels' -Parameters $parameters
}

function Get-SpecialFeed {
    $specialFeedIds
}

# Export only the functions using PowerShell standard verb-noun naming.
# Be sure to list each exported functions in the FunctionsToExport field of the module manifest file.
# This improves performance of command discovery in PowerShell.
Export-ModuleMember -Function *-*
