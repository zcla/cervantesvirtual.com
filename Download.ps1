function BuscaPaginas($url) {
    $wr = Invoke-WebRequest -Uri $url
    $html = $wr.Content | ConvertFrom-Html
    $links = $html.DescendantNodes() | Where-Object { $_.Name -eq 'a' }
    $result = [ordered]@{}
    foreach ($link in $links) {
        if ($link.InnerText) {
            $href = $link.Attributes['href'].Value
            $fullHref = "$url$href"

            # Link para uma página
            if ($href -match '[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}_\d+.htm') {
                if ($link.Attributes['target'].Value -eq '_blank') {
                    continue
                }
                $innerText = $link.InnerText -replace "`r`n", " " -replace "\s\s+", " "
                if ($result.$fullHref) {
                    if ($result.$fullHref.texto.GetType().Name -eq 'string') {
                        $result.$fullHref.texto = @($result.$fullHref.texto)
                    }
                    $result.$fullHref.texto += $innerText
                    Write-Host "$href => $innerText" -ForegroundColor DarkGray
                } else {
                    $result.$fullHref = [ordered]@{
                        urlBase = $url
                        url = $fullHref
                        texto = $innerText
                    }
                    Write-Host "$href => $innerText" -ForegroundColor Cyan
                }
            }

            # Link para uma obra
            if ($href -match '/FichaObra\.html\?Ref=') {
                Write-Host "$href" -ForegroundColor Yellow
                $urlObra = "$($url.Split('/')[0..2] -join '/')$href"
                Write-Host "=> $urlObra" -ForegroundColor Yellow
                $wrObra = Invoke-WebRequest -Uri $urlObra
                $htmlObra = $wrObra.Content | ConvertFrom-Html
                $linkCanonical = $htmlObra.DescendantNodes() | Where-Object { ($_.Name -eq 'link') -and ($_.Attributes['rel'].Value -eq 'canonical') }
                if ($linkCanonical.Count -ne 1) {
                    throw '$linkCanonical.Count -ne 1'
                }
                $urlCanonical = $linkCanonical[0].Attributes['href'].Value
                Write-Host "=> $urlCanonical" -ForegroundColor Yellow
                $wrCanonical = Invoke-WebRequest -Uri $urlCanonical
                $htmlCanonical = $wrCanonical.Content | ConvertFrom-Html
                $linkLeer = $htmlCanonical.DescendantNodes() | Where-Object { ($_.Name -eq 'a') -and ($_.OuterHtml -match 'Leer obra') }
                if ($linkLeer.Count -ne 1) {
                    throw '$linkLeer.Count -ne 1'
                }
                $urlLeer = $linkLeer[0].Attributes['href'].Value
                $paginasLeer = BuscaPaginas $urlLeer
                foreach ($key in $paginasLeer.Keys) {
                    $pagina = $paginasLeer.$key
                    $pagina.urlObra = $urlObra
                    $pagina.urlCanonical = $urlCanonical
                    if ($result[$pagina.url]) {
                        throw "Já existe!"
                    }
                    $result[$pagina.url] = $pagina
                }
            }
        }
    }
    return $result
}

function DownloadLivro($paginas, $outFolder) {
    $index = 0
    foreach ($key in $paginas.Keys) {
        $pagina = $paginas.$key
        Write-Host "$($pagina.url)" -ForegroundColor Cyan
        if ($pagina.urlAmpliada) {
            $urlAmpliada = $pagina.urlAmpliada
        } else {
            $urlSite = $pagina.url.Split('/')[0..2] -join '/'
            $wr = Invoke-WebRequest -Uri $pagina.url
            $html = $wr.Content | ConvertFrom-Html
            $links = $html.DescendantNodes() | Where-Object { ($_.Name -eq 'a') -and ($_.Attributes['href'].Value -match '^imagenes/') -and ($_.OuterHtml -match 'Ver imagen ampliada') }
            if ($links.Count -ne 1) {
                throw '$links.Count -ne 1'
            }
            $urlAmpliada = "$($pagina.urlBase)$($links[0].Attributes['href'].Value)"
            Write-Host "=> $urlAmpliada" -ForegroundColor Yellow
        }
        if ($pagina.urlImagem) {
            $urlImagem = $pagina.urlImagem
        } else {
            $wrAmpliada = Invoke-WebRequest -Uri $urlAmpliada
            $htmlAmpliada = $wrAmpliada.Content | ConvertFrom-Html
            $imagens = $htmlAmpliada.DescendantNodes() | Where-Object { $_.Name -eq 'img' }
            if ($imagens.Count -ne 1) {
                throw '$imagens.Count -ne 1'
            }
            $urlImagem = $imagens[0].Attributes['src'].Value
            $urlImagem = "$urlSite$urlImagem"
            Write-Host "=> $urlImagem" -ForegroundColor Yellow
        }
        $index++
        $strIndex = "$index".PadLeft(5, '0')
        $outFile = "$outFolder\img\$strIndex.$($urlImagem.Split('/')[-1])"
        if (-not (Test-Path $outFile)) {
            Invoke-WebRequest -Uri $urlImagem -OutFile $outFile
        }
        $pagina.urlAmpliada = $urlAmpliada
        $pagina.urlImagem = $urlImagem
        $paginas | ConvertTo-Json | Out-File "$outFolder\paginas.json"
    }
}

$livros = @(
    @{
        nome = "Escritos de Santa Teresa - Tomo Primero"
        url = "https://www.cervantesvirtual.com/obra-visor/escritos-de-santa-teresa-tomo-primero--0/html/"
    },
    @{
        nome = "Escritos de Santa Teresa - Tomo Segundo"
        url = "https://www.cervantesvirtual.com/obra-visor/escritos-de-santa-teresa-tomo-segundo--0/html/"
    }
)

foreach ($livro in $livros) {
    $outFolder = ".\$($livro.nome)"
	
    if (-not (Test-Path -Path $outFolder)) {
	    New-Item "$outFolder\img" -ItemType Directory -Force | Out-Null
    }

    if (Test-Path "$outFolder\paginas.json") {
        $paginas = Get-Content -Path "$outFolder\paginas.json" | ConvertFrom-Json -AsHashtable
    } else {
        $paginas = BuscaPaginas $livro.url
        $paginas | ConvertTo-Json | Out-File "$outFolder\paginas.json"
    }
    
    DownloadLivro $paginas $outFolder

    if (-not (Test-Path "$outFolder\noocr.pdf")) {
        Write-Host "Criando o PDF" -ForegroundColor Cyan
        wsl --cd $outFolder img2pdf ./img/*.jpg --output ./noocr.pdf
    }

    if (-not (Test-Path "$outFolder\ocr.pdf")) {
        Write-Host "Executando o OCR no PDF" -ForegroundColor Cyan
        wsl --cd $outFolder ocrmypdf -l spa ./noocr.pdf ./ocr.pdf
    }
}
