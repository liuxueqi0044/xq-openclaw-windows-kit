#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

Describe 'M3 offline Chinese content' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $guide = Join-Path $repo 'content\guide'
        $html = @(Get-ChildItem -LiteralPath $guide -Filter '*.html' -File)
        $all = ($html | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    }

    It 'has one entry page and five numbered main steps' {
        (Test-Path (Join-Path $guide '00-开始这里.html')) | Should -BeTrue
        ($all -split '第 [1-5] 步' | Measure-Object).Count | Should -BeGreaterThan 5
        $entry = Get-Content (Join-Path $guide '00-开始这里.html') -Raw
        ([regex]::Matches($entry,'class="step"')).Count | Should -Be 5
    }

    It 'contains only local resources and valid internal links' {
        $all | Should -Not -Match '(?i)https?://|<iframe|<script|@import|fonts\.google'
        foreach ($page in $html) {
            foreach ($href in [regex]::Matches((Get-Content $page.FullName -Raw),'href="([^"]+)"')) {
                $target = $href.Groups[1].Value
                if ($target -notmatch '^(?i)(mailto:|#)') { (Test-Path (Join-Path $page.DirectoryName $target)) | Should -BeTrue -Because $target }
            }
        }
    }

    It 'has no orphan guide page' {
        $entryPath = (Resolve-Path (Join-Path $guide '00-开始这里.html')).Path
        $pending = [System.Collections.Generic.Queue[string]]::new()
        $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $pending.Enqueue($entryPath)
        while ($pending.Count -gt 0) {
            $pagePath = $pending.Dequeue()
            if (-not $visited.Add($pagePath)) { continue }
            $pageDirectory = Split-Path -Parent $pagePath
            foreach ($href in [regex]::Matches((Get-Content -LiteralPath $pagePath -Raw),'href="([^"]+)"')) {
                $target = $href.Groups[1].Value
                if ($target -match '^(?i)(mailto:|#)' -or $target -notmatch '(?i)\.html$') { continue }
                $resolved = [IO.Path]::GetFullPath((Join-Path $pageDirectory $target))
                if ((Test-Path -LiteralPath $resolved -PathType Leaf) -and -not $visited.Contains($resolved)) { $pending.Enqueue($resolved) }
            }
        }
        foreach ($page in $html) {
            $visited.Contains($page.FullName) | Should -BeTrue -Because "$($page.Name) must be reachable from the entry page"
        }
    }

    It 'shows version and required boundary statements' {
        $all | Should -Match 'XQ v0\.1\.0'
        $all | Should -Match 'SOURCE-AND-VERSION\.json|包内来源证明'
        $all | Should -Match '非官方|不是 OpenClaw 官方|independent'
        $all | Should -Match 'API Key|凭据'
        $all | Should -Match '费用|收费'
        $all | Should -Match '不.*提权|不.*远控'
        $all | Should -Match 'OpenClawGateway'
        $all | Should -Match '免费获取|免费'
        $all | Should -Match '最小权限|无敏感数据'
        $all | Should -Match '备份重要文件|备份'
        $all | Should -Match 'Node Mode|system\.run'
        $all | Should -Match '屏幕.*相机|相机.*屏幕'
        $all | Should -Match '终端|网络'
    }

    It 'does not drift from productBoundary in the product manifest' {
        $boundary = (Get-Content (Join-Path $repo 'manifest\product-config.json') -Raw | ConvertFrom-Json).productBoundary
        ($all + (Get-Content (Join-Path $repo 'content\README.txt') -Raw)) | Should -Match ([regex]::Escape($boundary.productName))
        $all | Should -Match 'not OpenClaw|不是 OpenClaw 官方|非官方'
        $all | Should -Match 'API Key|凭据'
        $all | Should -Match '远控|远程控制'
        $all | Should -Match '自动.*修复|只读'
        $all | Should -Match '费用|收费'
        $all | Should -Match '官方授权|官方商品|不代表.*授权|不.*授权'
    }

    It 'keeps CSS and pages usable without a remote font' {
        (Get-Content (Join-Path $repo 'content\assets\style.css') -Raw) | Should -Not -Match 'Noto|woff|fonts\.google'
        $all | Should -Match 'alt=|<html lang=' -Because 'all pages declare language; image assets are intentionally not required'
    }
}
