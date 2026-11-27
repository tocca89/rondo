import Foundation

/// Lightweight in-code localization. Keys are the Italian strings; columns follow `Lang.others`.
enum Lang {
    static let all: [(code: String, name: String)] = [
        ("en", "English"), ("it", "Italiano"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("pt", "Português"),
    ]
    static let others = ["en", "es", "fr", "de", "pt"]

    /// Current language code: the one chosen in Settings, otherwise the first supported system language, otherwise English.
    static var current: String {
        let chosen = UserDefaults.standard.string(forKey: "language") ?? ""
        if all.contains(where: { $0.code == chosen }) { return chosen }
        for pref in Locale.preferredLanguages {
            let code = String(pref.prefix(2))
            if all.contains(where: { $0.code == code }) { return code }
        }
        return "en"
    }

    /// Makes system-provided UI (open panels, alerts) follow the chosen language at next launch.
    static func apply(_ code: String) {
        UserDefaults.standard.set(code, forKey: "language")
        if code.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
    }
}

func L(_ key: String, _ args: CVarArg...) -> String {
    let lang = Lang.current
    var s = key
    if lang != "it", let row = translations[key], let i = Lang.others.firstIndex(of: lang), i < row.count {
        s = row[i]
    }
    return args.isEmpty ? s : String(format: s, arguments: args)
}

// en, es, fr, de, pt
private let translations: [String: [String]] = [
    // Wheels & menu
    "Converti": ["Convert", "Convertir", "Convertir", "Konvertieren", "Converter"],
    "Strumenti": ["Tools", "Herramientas", "Outils", "Werkzeuge", "Ferramentas"],
    "Azioni": ["Actions", "Acciones", "Actions", "Aktionen", "Ações"],
    "Ruote durante il trascinamento": ["Wheels while dragging", "Ruedas al arrastrar", "Roues pendant le glisser", "Räder beim Ziehen", "Rodas ao arrastar"],
    "Apri selezione del Finder": ["Open Finder Selection", "Abrir selección del Finder", "Ouvrir la sélection du Finder", "Finder-Auswahl öffnen", "Abrir seleção do Finder"],
    "Scegli file…": ["Choose Files…", "Elegir archivos…", "Choisir des fichiers…", "Dateien wählen…", "Escolher arquivos…"],
    "Mostra Float": ["Show Float", "Mostrar Float", "Afficher Float", "Float anzeigen", "Mostrar Float"],
    "Come si usa": ["How to Use", "Cómo se usa", "Mode d’emploi", "So funktioniert’s", "Como usar"],
    "Impostazioni…": ["Settings…", "Ajustes…", "Réglages…", "Einstellungen…", "Ajustes…"],
    "Esci da Rondo": ["Quit Rondo", "Salir de Rondo", "Quitter Rondo", "Rondo beenden", "Sair do Rondo"],
    "Modifica": ["Edit", "Edición", "Édition", "Bearbeiten", "Editar"],
    "Taglia": ["Cut", "Cortar", "Couper", "Ausschneiden", "Recortar"],
    "Copia": ["Copy", "Copiar", "Copier", "Kopieren", "Copiar"],
    "Incolla": ["Paste", "Pegar", "Coller", "Einsetzen", "Colar"],
    "Seleziona tutto": ["Select All", "Seleccionar todo", "Tout sélectionner", "Alles auswählen", "Selecionar tudo"],
    "Chiudi finestra": ["Close Window", "Cerrar ventana", "Fermer la fenêtre", "Fenster schließen", "Fechar janela"],
    "Scegli i file da convertire": ["Choose the files to convert", "Elige los archivos que quieres convertir", "Choisissez les fichiers à convertir", "Wähle die zu konvertierenden Dateien", "Escolha os arquivos para converter"],
    "Impostazioni di Rondo": ["Rondo Settings", "Ajustes de Rondo", "Réglages de Rondo", "Rondo-Einstellungen", "Ajustes do Rondo"],
    "Benvenuto in Rondo": ["Welcome to Rondo", "Te damos la bienvenida a Rondo", "Bienvenue dans Rondo", "Willkommen bei Rondo", "Boas-vindas ao Rondo"],

    // Settings
    "Ruote": ["Wheels", "Ruedas", "Roues", "Räder", "Rodas"],
    "Mostra le ruote mentre trascini un file": ["Show wheels while dragging a file", "Mostrar las ruedas al arrastrar un archivo", "Afficher les roues pendant le glisser d’un fichier", "Räder beim Ziehen einer Datei anzeigen", "Mostrar as rodas ao arrastar um arquivo"],
    "Due ruote usano lo stesso tasto": ["Two wheels use the same key", "Dos ruedas usan la misma tecla", "Deux roues utilisent la même touche", "Zwei Räder nutzen dieselbe Taste", "Duas rodas usam a mesma tecla"],
    "Output": ["Output", "Salida", "Sortie", "Ausgabe", "Saída"],
    "Salva i file": ["Save files", "Guardar archivos", "Enregistrer les fichiers", "Dateien sichern", "Salvar arquivos"],
    "Accanto all'originale": ["Next to the original", "Junto al original", "À côté de l’original", "Neben dem Original", "Ao lado do original"],
    "In Download": ["In Downloads", "En Descargas", "Dans Téléchargements", "In „Downloads“", "Em Transferências"],
    "In una cartella…": ["In a folder…", "En una carpeta…", "Dans un dossier…", "In einem Ordner…", "Em uma pasta…"],
    "Nessuna cartella": ["No folder", "Ninguna carpeta", "Aucun dossier", "Kein Ordner", "Nenhuma pasta"],
    "Scegli…": ["Choose…", "Elegir…", "Choisir…", "Wählen…", "Escolher…"],
    "Qualità JPG/HEIC/WebP": ["JPG/HEIC/WebP quality", "Calidad JPG/HEIC/WebP", "Qualité JPG/HEIC/WebP", "JPG/HEIC/WebP-Qualität", "Qualidade JPG/HEIC/WebP"],
    "Risoluzione PDF → immagini": ["PDF → image resolution", "Resolución PDF → imágenes", "Résolution PDF → images", "Auflösung PDF → Bilder", "Resolução PDF → imagens"],
    "Mostra nel Finder al termine": ["Reveal in Finder when done", "Mostrar en el Finder al terminar", "Afficher dans le Finder à la fin", "Danach im Finder zeigen", "Mostrar no Finder ao terminar"],
    "Suono al termine": ["Play sound when done", "Sonido al terminar", "Son à la fin", "Ton nach Abschluss", "Som ao terminar"],
    "Sistema": ["System", "Sistema", "Système", "System", "Sistema"],
    "Apri all'avvio del Mac": ["Open at login", "Abrir al iniciar sesión", "Ouvrir à l’ouverture de session", "Beim Anmelden öffnen", "Abrir ao iniciar sessão"],
    "non trovato": ["not found", "no encontrado", "introuvable", "nicht gefunden", "não encontrado"],
    "Percorso ffmpeg personalizzato": ["Custom ffmpeg path", "Ruta de ffmpeg personalizada", "Chemin ffmpeg personnalisé", "Eigener ffmpeg-Pfad", "Caminho do ffmpeg personalizado"],
    "automatico": ["automatic", "automático", "automatique", "automatisch", "automático"],
    "Hot key globale: ⌃⌥R apre la ruota sui file selezionati nel Finder.": [
        "Global hot key: ⌃⌥R opens the wheel for the files selected in Finder.",
        "Atajo global: ⌃⌥R abre la rueda con los archivos seleccionados en el Finder.",
        "Raccourci global : ⌃⌥R ouvre la roue pour les fichiers sélectionnés dans le Finder.",
        "Globaler Kurzbefehl: ⌃⌥R öffnet das Rad für die im Finder ausgewählten Dateien.",
        "Atalho global: ⌃⌥R abre a roda com os arquivos selecionados no Finder."],
    "Lingua": ["Language", "Idioma", "Langue", "Sprache", "Idioma"],
    "Automatica (sistema)": ["Automatic (system)", "Automático (sistema)", "Automatique (système)", "Automatisch (System)", "Automático (sistema)"],
    "Alcuni testi di sistema cambiano al prossimo avvio.": [
        "Some system texts change at next launch.", "Algunos textos del sistema cambian en el próximo inicio.",
        "Certains textes système changent au prochain lancement.", "Einige Systemtexte ändern sich beim nächsten Start.",
        "Alguns textos do sistema mudam na próxima abertura."],

    // Welcome
    "Il convertitore di file offline, a portata di trascinamento.": [
        "The offline file converter, one drag away.", "El conversor de archivos sin conexión, a un arrastre de distancia.",
        "Le convertisseur de fichiers hors ligne, à portée de glisser.", "Der Offline-Dateikonverter – nur einen Zug entfernt.",
        "O conversor de arquivos offline, a um arrastar de distância."],
    "Inizia a trascinare un file": ["Start dragging a file", "Empieza a arrastrar un archivo", "Commencez à glisser un fichier", "Beginne, eine Datei zu ziehen", "Comece a arrastar um arquivo"],
    "Dal Finder, dalla Scrivania o da qualsiasi app.": ["From Finder, the Desktop or any app.", "Desde el Finder, el Escritorio o cualquier app.", "Depuis le Finder, le Bureau ou n’importe quelle app.", "Aus dem Finder, vom Schreibtisch oder aus jeder App.", "Do Finder, da Mesa ou de qualquer app."],
    "Premi un tasto mentre trascini": ["Press a key while dragging", "Pulsa una tecla mientras arrastras", "Appuyez sur une touche pendant le glisser", "Drücke beim Ziehen eine Taste", "Pressione uma tecla enquanto arrasta"],
    "Compare una ruota attorno al cursore. Puoi lasciare il tasto.": [
        "A wheel appears around the pointer. You can let go of the key.", "Aparece una rueda alrededor del puntero. Puedes soltar la tecla.",
        "Une roue apparaît autour du pointeur. Vous pouvez relâcher la touche.", "Ein Rad erscheint um den Zeiger. Du kannst die Taste loslassen.",
        "Uma roda aparece em volta do ponteiro. Você pode soltar a tecla."],
    "Rilascia sullo spicchio": ["Drop on a slice", "Suelta sobre un sector", "Déposez sur un secteur", "Auf einem Segment ablegen", "Solte sobre um setor"],
    "Il risultato viene salvato come nuova copia. Al centro = annulla.": [
        "The result is saved as a new copy. Center = cancel.", "El resultado se guarda como una copia nueva. Centro = cancelar.",
        "Le résultat est enregistré comme nouvelle copie. Centre = annuler.", "Das Ergebnis wird als neue Kopie gesichert. Mitte = abbrechen.",
        "O resultado é salvo como uma nova cópia. Centro = cancelar."],
    "formati: immagini, audio, video, PDF, documenti, tabelle, sottotitoli, archivi": [
        "formats: images, audio, video, PDF, documents, tables, subtitles, archives",
        "formatos: imágenes, audio, vídeo, PDF, documentos, tablas, subtítulos, archivos comprimidos",
        "formats : images, audio, vidéo, PDF, documents, tableaux, sous-titres, archives",
        "Formate: Bilder, Audio, Video, PDF, Dokumente, Tabellen, Untertitel, Archive",
        "formatos: imagens, áudio, vídeo, PDF, documentos, tabelas, legendas, arquivos compactados"],
    "comprimi, ridimensiona, ruota, scontorna, unisci/dividi PDF, info…": [
        "compress, resize, rotate, cut out, merge/split PDF, info…",
        "comprimir, redimensionar, girar, quitar fondo, unir/dividir PDF, info…",
        "compresser, redimensionner, pivoter, détourer, fusionner/scinder des PDF, infos…",
        "komprimieren, skalieren, drehen, freistellen, PDF zusammenfügen/teilen, Info…",
        "comprimir, redimensionar, girar, remover fundo, juntar/dividir PDF, info…"],
    "AirDrop, Float, copia, sposta, percorso, Terminale": [
        "AirDrop, Float, copy, move, path, Terminal", "AirDrop, Float, copiar, mover, ruta, Terminal",
        "AirDrop, Float, copier, déplacer, chemin, Terminal", "AirDrop, Float, kopieren, bewegen, Pfad, Terminal",
        "AirDrop, Float, copiar, mover, caminho, Terminal"],
    "Senza trascinare: seleziona i file nel Finder e premi ⌃⌥R. Usa le frecce, Tab per cambiare ruota, Invio per confermare.": [
        "Without dragging: select files in Finder and press ⌃⌥R. Use the arrow keys, Tab to switch wheel, Return to confirm.",
        "Sin arrastrar: selecciona archivos en el Finder y pulsa ⌃⌥R. Usa las flechas, Tab para cambiar de rueda e Intro para confirmar.",
        "Sans glisser : sélectionnez des fichiers dans le Finder et appuyez sur ⌃⌥R. Flèches pour choisir, Tab pour changer de roue, Entrée pour confirmer.",
        "Ohne Ziehen: Dateien im Finder auswählen und ⌃⌥R drücken. Pfeiltasten zum Wählen, Tab zum Wechseln des Rads, Return zum Bestätigen.",
        "Sem arrastar: selecione arquivos no Finder e pressione ⌃⌥R. Use as setas, Tab para trocar de roda e Return para confirmar."],
    "Per tutti i formati audio/video installa ffmpeg:  brew install ffmpeg": [
        "For every audio/video format install ffmpeg:  brew install ffmpeg",
        "Para todos los formatos de audio/vídeo instala ffmpeg:  brew install ffmpeg",
        "Pour tous les formats audio/vidéo, installez ffmpeg :  brew install ffmpeg",
        "Für alle Audio-/Videoformate ffmpeg installieren:  brew install ffmpeg",
        "Para todos os formatos de áudio/vídeo instale o ffmpeg:  brew install ffmpeg"],
    "Inizia": ["Get Started", "Empezar", "Commencer", "Los geht’s", "Começar"],

    // Practice (welcome)
    "Prova adesso": ["Try it now", "Pruébalo ahora", "Essayez maintenant", "Jetzt ausprobieren", "Experimente agora"],
    "Trascina questa immagine e, mentre la tieni, premi %@": [
        "Drag this image and, while holding it, press %@", "Arrastra esta imagen y, mientras la sostienes, pulsa %@",
        "Faites glisser cette image et, sans la lâcher, appuyez sur %@", "Ziehe dieses Bild und drücke dabei %@",
        "Arraste esta imagem e, enquanto a segura, pressione %@"],
    "Ora premi %@": ["Now press %@", "Ahora pulsa %@", "Appuyez maintenant sur %@", "Jetzt %@ drücken", "Agora pressione %@"],
    "Rilascia su uno spicchio, ad esempio JPG": [
        "Drop it on a slice, for example JPG", "Suéltala sobre un sector, por ejemplo JPG",
        "Déposez-la sur un secteur, par exemple JPG", "Lege es auf einem Segment ab, z. B. JPG",
        "Solte-a em um setor, por exemplo JPG"],
    "Ce l'hai fatta! Hai creato %@": ["You did it! You created %@", "¡Lo lograste! Has creado %@", "Bravo ! Vous avez créé %@", "Geschafft! Du hast %@ erstellt", "Conseguiu! Você criou %@"],
    "Mostra": ["Show", "Mostrar", "Afficher", "Zeigen", "Mostrar"],

    // Updates & About
    "Informazioni su Rondo": ["About Rondo", "Acerca de Rondo", "À propos de Rondo", "Über Rondo", "Sobre o Rondo"],
    "Controlla aggiornamenti…": ["Check for Updates…", "Buscar actualizaciones…", "Rechercher des mises à jour…", "Nach Updates suchen…", "Verificar atualizações…"],
    "Controlla gli aggiornamenti automaticamente": ["Check for updates automatically", "Buscar actualizaciones automáticamente", "Rechercher les mises à jour automatiquement", "Automatisch nach Updates suchen", "Verificar atualizações automaticamente"],
    "Controlla ora": ["Check Now", "Buscar ahora", "Vérifier", "Jetzt prüfen", "Verificar agora"],
    "È disponibile Rondo %@": ["Rondo %@ is available", "Rondo %@ está disponible", "Rondo %@ est disponible", "Rondo %@ ist verfügbar", "O Rondo %@ está disponível"],
    "Hai la versione %@.": ["You have version %@.", "Tienes la versión %@.", "Vous avez la version %@.", "Du hast Version %@.", "Você tem a versão %@."],
    "Scarica": ["Download", "Descargar", "Télécharger", "Laden", "Baixar"],
    "Più tardi": ["Later", "Más tarde", "Plus tard", "Später", "Mais tarde"],
    "Salta questa versione": ["Skip This Version", "Omitir esta versión", "Ignorer cette version", "Diese Version überspringen", "Ignorar esta versão"],
    "Rondo è aggiornato": ["Rondo is up to date", "Rondo está actualizado", "Rondo est à jour", "Rondo ist aktuell", "O Rondo está atualizado"],
    "Stai usando l'ultima versione (%@).": ["You’re using the latest version (%@).", "Estás usando la última versión (%@).", "Vous utilisez la dernière version (%@).", "Du verwendest die neueste Version (%@).", "Você está usando a versão mais recente (%@)."],
    "Impossibile controllare gli aggiornamenti": ["Couldn’t check for updates", "No se pudieron buscar actualizaciones", "Impossible de rechercher les mises à jour", "Suche nach Updates fehlgeschlagen", "Não foi possível verificar atualizações"],
    "Trascina. Tocca. Fatto.": ["Drag. Tap. Done.", "Arrastra. Toca. Listo.", "Glissez. Touchez. C’est fait.", "Ziehen. Tippen. Fertig.", "Arraste. Toque. Pronto."],
    "Versione %@": ["Version %@", "Versión %@", "Version %@", "Version %@", "Versão %@"],
    "Creato da": ["Made by", "Creado por", "Créé par", "Erstellt von", "Criado por"],
    "Codice sorgente": ["Source Code", "Código fuente", "Code source", "Quellcode", "Código-fonte"],
    "Segnala un problema": ["Report an Issue", "Informar de un problema", "Signaler un problème", "Problem melden", "Relatar um problema"],
    "Software libero con licenza MIT": ["Free software under the MIT license", "Software libre con licencia MIT", "Logiciel libre sous licence MIT", "Freie Software unter MIT-Lizenz", "Software livre sob licença MIT"],

    // ffmpeg installer
    "Altri formati…": ["More Formats…", "Más formatos…", "Plus de formats…", "Mehr Formate…", "Mais formatos…"],
    "Altri formati audio e video": ["More Audio & Video Formats", "Más formatos de audio y vídeo", "Plus de formats audio et vidéo", "Mehr Audio- und Videoformate", "Mais formatos de áudio e vídeo"],
    "Sblocca tutti i formati audio e video": ["Unlock every audio and video format", "Desbloquea todos los formatos de audio y vídeo", "Débloquez tous les formats audio et vidéo", "Alle Audio- und Videoformate freischalten", "Desbloqueie todos os formatos de áudio e vídeo"],
    "Rondo usa ffmpeg, un componente gratuito e open source, per MP3, OGG, Opus, WebM, MKV, AVI, GIF e per gli strumenti audio e video.": [
        "Rondo uses ffmpeg, a free and open-source component, for MP3, OGG, Opus, WebM, MKV, AVI, GIF and the audio and video tools.",
        "Rondo usa ffmpeg, un componente gratuito y de código abierto, para MP3, OGG, Opus, WebM, MKV, AVI, GIF y las herramientas de audio y vídeo.",
        "Rondo utilise ffmpeg, un composant libre et gratuit, pour MP3, OGG, Opus, WebM, MKV, AVI, GIF et les outils audio et vidéo.",
        "Rondo nutzt ffmpeg, eine kostenlose Open-Source-Komponente, für MP3, OGG, Opus, WebM, MKV, AVI, GIF und die Audio- und Videowerkzeuge.",
        "O Rondo usa o ffmpeg, um componente gratuito e de código aberto, para MP3, OGG, Opus, WebM, MKV, AVI, GIF e as ferramentas de áudio e vídeo."],
    "Installa con Homebrew": ["Install with Homebrew", "Instalar con Homebrew", "Installer avec Homebrew", "Mit Homebrew installieren", "Instalar com o Homebrew"],
    "Esegue «brew install ffmpeg». Richiede qualche minuto.": ["Runs “brew install ffmpeg”. Takes a few minutes.", "Ejecuta «brew install ffmpeg». Tarda unos minutos.", "Exécute « brew install ffmpeg ». Prend quelques minutes.", "Führt „brew install ffmpeg“ aus. Dauert ein paar Minuten.", "Executa “brew install ffmpeg”. Leva alguns minutos."],
    "Scarica ffmpeg (circa 29 MB)": ["Download ffmpeg (about 29 MB)", "Descargar ffmpeg (unos 29 MB)", "Télécharger ffmpeg (environ 29 Mo)", "ffmpeg laden (ca. 29 MB)", "Baixar o ffmpeg (cerca de 29 MB)"],
    "Versione per Apple silicon da %@ (terze parti), verificata con SHA-256 e salvata nella cartella di Rondo.": [
        "Apple silicon build from %@ (third party), checked with SHA-256 and stored in Rondo’s folder.",
        "Versión para Apple silicon de %@ (terceros), verificada con SHA-256 y guardada en la carpeta de Rondo.",
        "Version Apple silicon de %@ (tiers), vérifiée par SHA-256 et enregistrée dans le dossier de Rondo.",
        "Apple-silicon-Build von %@ (Drittanbieter), per SHA-256 geprüft und im Rondo-Ordner gespeichert.",
        "Versão para Apple silicon de %@ (terceiros), verificada com SHA-256 e salva na pasta do Rondo."],
    "Preferisci Homebrew? Ecco come installarlo": ["Prefer Homebrew? Here’s how to install it", "¿Prefieres Homebrew? Así se instala", "Vous préférez Homebrew ? Voici comment l’installer", "Lieber Homebrew? So installierst du es", "Prefere o Homebrew? Veja como instalar"],
    "Installa": ["Install", "Instalar", "Installer", "Installieren", "Instalar"],
    "Installa…": ["Install…", "Instalar…", "Installer…", "Installieren…", "Instalar…"],
    "Installa ffmpeg…": ["Install ffmpeg…", "Instalar ffmpeg…", "Installer ffmpeg…", "ffmpeg installieren…", "Instalar ffmpeg…"],
    "Installazione con Homebrew…": ["Installing with Homebrew…", "Instalando con Homebrew…", "Installation avec Homebrew…", "Installation mit Homebrew…", "Instalando com o Homebrew…"],
    "Download di ffmpeg…": ["Downloading ffmpeg…", "Descargando ffmpeg…", "Téléchargement de ffmpeg…", "ffmpeg wird geladen…", "Baixando o ffmpeg…"],
    "Verifica dell'impronta SHA-256…": ["Checking the SHA-256 checksum…", "Verificando la suma SHA-256…", "Vérification de l’empreinte SHA-256…", "SHA-256-Prüfsumme wird geprüft…", "Verificando o SHA-256…"],
    "Installazione…": ["Installing…", "Instalando…", "Installation…", "Installation…", "Instalando…"],
    "Download non riuscito": ["Download failed", "Error en la descarga", "Échec du téléchargement", "Download fehlgeschlagen", "Falha no download"],
    "Impronta SHA-256 non disponibile": ["SHA-256 checksum not available", "Suma SHA-256 no disponible", "Empreinte SHA-256 indisponible", "SHA-256-Prüfsumme nicht verfügbar", "SHA-256 indisponível"],
    "L'impronta SHA-256 non corrisponde: file scartato": ["SHA-256 checksum mismatch: file discarded", "La suma SHA-256 no coincide: archivo descartado", "L’empreinte SHA-256 ne correspond pas : fichier supprimé", "SHA-256-Prüfsumme stimmt nicht: Datei verworfen", "O SHA-256 não confere: arquivo descartado"],
    "ffmpeg non trovato nell'archivio": ["ffmpeg not found in the archive", "ffmpeg no encontrado en el archivo", "ffmpeg introuvable dans l’archive", "ffmpeg nicht im Archiv gefunden", "ffmpeg não encontrado no arquivo"],
    "ffmpeg è pronto! I nuovi formati compaiono già nella ruota.": ["ffmpeg is ready! The new formats already show up in the wheel.", "¡ffmpeg está listo! Los nuevos formatos ya aparecen en la rueda.", "ffmpeg est prêt ! Les nouveaux formats apparaissent déjà dans la roue.", "ffmpeg ist bereit! Die neuen Formate erscheinen schon im Rad.", "O ffmpeg está pronto! Os novos formatos já aparecem na roda."],
    "Chiudi": ["Close", "Cerrar", "Fermer", "Schließen", "Fechar"],
    "Per tutti i formati audio e video serve ffmpeg.": ["Every audio and video format needs ffmpeg.", "Para todos los formatos de audio y vídeo hace falta ffmpeg.", "Tous les formats audio et vidéo nécessitent ffmpeg.", "Für alle Audio- und Videoformate wird ffmpeg benötigt.", "Todos os formatos de áudio e vídeo precisam do ffmpeg."],

    // Wheel
    "Nessuna opzione\nper questi file": ["No options\nfor these files", "Sin opciones\npara estos archivos", "Aucune option\npour ces fichiers", "Keine Optionen\nfür diese Dateien", "Nenhuma opção\npara estes arquivos"],
    "%d elementi": ["%d items", "%d elementos", "%d éléments", "%d Objekte", "%d itens"],

    // Wheel items
    "Comprimi": ["Compress", "Comprimir", "Compresser", "Komprimieren", "Comprimir"],
    "Riduci 50%": ["Shrink 50%", "Reducir 50%", "Réduire 50 %", "Verkleinern 50 %", "Reduzir 50%"],
    "Ruota 90°": ["Rotate 90°", "Girar 90°", "Pivoter 90°", "90° drehen", "Girar 90°"],
    "Specchia": ["Flip", "Voltear", "Miroir", "Spiegeln", "Espelhar"],
    "Bianco e nero": ["Black & White", "Blanco y negro", "Noir et blanc", "Schwarzweiß", "Preto e branco"],
    "Rimuovi metadati": ["Remove Metadata", "Quitar metadatos", "Supprimer métadonnées", "Metadaten entfernen", "Remover metadados"],
    "Rimuovi sfondo": ["Remove Background", "Quitar fondo", "Supprimer le fond", "Hintergrund entfernen", "Remover fundo"],
    "Unisci in PDF": ["Combine into PDF", "Unir en PDF", "Combiner en PDF", "Zu PDF vereinen", "Juntar em PDF"],
    "Normalizza": ["Normalize", "Normalizar", "Normaliser", "Normalisieren", "Normalizar"],
    "Togli silenzi": ["Trim Silence", "Quitar silencios", "Couper les silences", "Stille entfernen", "Remover silêncios"],
    "Velocità 1.5×": ["Speed 1.5×", "Velocidad 1,5×", "Vitesse 1,5×", "Tempo 1,5×", "Velocidade 1,5×"],
    "Velocità 2×": ["Speed 2×", "Velocidad 2×", "Vitesse 2×", "Tempo 2×", "Velocidade 2×"],
    "Metà risoluzione": ["Half Resolution", "Mitad de resolución", "Demi-résolution", "Halbe Auflösung", "Metade da resolução"],
    "Togli audio": ["Remove Audio", "Quitar audio", "Supprimer l’audio", "Ton entfernen", "Remover áudio"],
    "Estrai audio": ["Extract Audio", "Extraer audio", "Extraire l’audio", "Audio extrahieren", "Extrair áudio"],
    "Fotogramma": ["Still Frame", "Fotograma", "Image fixe", "Standbild", "Quadro"],
    "Unisci": ["Merge", "Unir", "Fusionner", "Zusammenfügen", "Juntar"],
    "Dividi pagine": ["Split Pages", "Dividir páginas", "Scinder les pages", "Seiten teilen", "Dividir páginas"],
    "Ruota pagine": ["Rotate Pages", "Girar páginas", "Pivoter les pages", "Seiten drehen", "Girar páginas"],
    "Prima pagina": ["First Page", "Primera página", "Première page", "Erste Seite", "Primeira página"],
    "Conta parole": ["Word Count", "Contar palabras", "Compter les mots", "Wörter zählen", "Contar palavras"],
    "Conteggio": ["Count", "Recuento", "Comptage", "Zählung", "Contagem"],
    "Estrai": ["Extract", "Extraer", "Extraire", "Entpacken", "Extrair"],
    "Info": ["Info", "Info", "Infos", "Info", "Info"],
    "Informazioni": ["Information", "Información", "Informations", "Informationen", "Informações"],
    "Copia percorso": ["Copy Path", "Copiar ruta", "Copier le chemin", "Pfad kopieren", "Copiar caminho"],
    "Sposta in…": ["Move to…", "Mover a…", "Déplacer vers…", "Bewegen nach…", "Mover para…"],
    "Copia in…": ["Copy to…", "Copiar a…", "Copier vers…", "Kopieren nach…", "Copiar para…"],
    "Terminale": ["Terminal", "Terminal", "Terminal", "Terminal", "Terminal"],
    "Mostra nel Finder": ["Show in Finder", "Mostrar en el Finder", "Afficher dans le Finder", "Im Finder zeigen", "Mostrar no Finder"],

    // Results
    "Copiato negli appunti": ["Copied to clipboard", "Copiado al portapapeles", "Copié dans le presse-papiers", "In die Zwischenablage kopiert", "Copiado para a área de transferência"],
    "Percorso copiato": ["Path copied", "Ruta copiada", "Chemin copié", "Pfad kopiert", "Caminho copiado"],
    "Spostato": ["Moved", "Movido", "Déplacé", "Bewegt", "Movido"],
    "Copiato": ["Copied", "Copiado", "Copié", "Kopiert", "Copiado"],
    "Sposta qui": ["Move Here", "Mover aquí", "Déplacer ici", "Hierher bewegen", "Mover para cá"],
    "Copia qui": ["Copy Here", "Copiar aquí", "Copier ici", "Hierher kopieren", "Copiar para cá"],
    "Scegli dove spostare %d elementi": ["Choose where to move %d items", "Elige dónde mover %d elementos", "Choisissez où déplacer %d éléments", "Wähle, wohin %d Objekte bewegt werden", "Escolha para onde mover %d itens"],
    "Scegli dove copiare %d elementi": ["Choose where to copy %d items", "Elige dónde copiar %d elementos", "Choisissez où copier %d éléments", "Wähle, wohin %d Objekte kopiert werden", "Escolha para onde copiar %d itens"],
    "Fatto": ["Done", "Hecho", "Terminé", "Fertig", "Pronto"],
    "Salvato: %@": ["Saved: %@", "Guardado: %@", "Enregistré : %@", "Gesichert: %@", "Salvo: %@"],
    "%d file creati": ["%d files created", "%d archivos creados", "%d fichiers créés", "%d Dateien erstellt", "%d arquivos criados"],
    "Trascina qui i file da tenere a portata di mano": ["Drop files here to keep them handy", "Suelta aquí archivos para tenerlos a mano", "Déposez ici les fichiers à garder sous la main", "Dateien hier ablegen, um sie griffbereit zu haben", "Solte aqui arquivos para tê-los à mão"],
    "Trascina fuori i file": ["Drag files out", "Arrastra los archivos fuera", "Faites glisser les fichiers vers l’extérieur", "Dateien herausziehen", "Arraste os arquivos para fora"],
    "Svuota": ["Clear", "Vaciar", "Vider", "Leeren", "Esvaziar"],
    "%d parole · %d caratteri · %d righe": ["%d words · %d characters · %d lines", "%d palabras · %d caracteres · %d líneas", "%d mots · %d caractères · %d lignes", "%d Wörter · %d Zeichen · %d Zeilen", "%d palavras · %d caracteres · %d linhas"],

    // Info
    "Elementi": ["Items", "Elementos", "Éléments", "Objekte", "Itens"],
    "Dimensione": ["Size", "Tamaño", "Taille", "Größe", "Tamanho"],
    "Creato": ["Created", "Creado", "Créé", "Erstellt", "Criado"],
    "Modificato": ["Modified", "Modificado", "Modifié", "Geändert", "Modificado"],
    "Pixel": ["Pixels", "Píxeles", "Pixels", "Pixel", "Pixels"],
    "Colore": ["Color", "Color", "Couleur", "Farbe", "Cor"],
    "Fotocamera": ["Camera", "Cámara", "Appareil photo", "Kamera", "Câmera"],
    "Scattata": ["Taken", "Tomada", "Prise le", "Aufgenommen", "Tirada"],
    "⚠︎ Contiene posizione GPS": ["⚠︎ Contains GPS location", "⚠︎ Contiene ubicación GPS", "⚠︎ Contient une position GPS", "⚠︎ Enthält GPS-Standort", "⚠︎ Contém localização GPS"],
    "Pagine": ["Pages", "Páginas", "Pages", "Seiten", "Páginas"],
    "Titolo": ["Title", "Título", "Titre", "Titel", "Título"],
    "Autore": ["Author", "Autor", "Auteur", "Autor", "Autor"],
    "Protetto da password": ["Password protected", "Protegido con contraseña", "Protégé par mot de passe", "Passwortgeschützt", "Protegido por senha"],
    "Durata": ["Duration", "Duración", "Durée", "Dauer", "Duração"],

    // Errors
    "AirDrop non disponibile": ["AirDrop isn’t available", "AirDrop no está disponible", "AirDrop n’est pas disponible", "AirDrop ist nicht verfügbar", "AirDrop não está disponível"],
    "Terminale non trovato": ["Terminal not found", "Terminal no encontrado", "Terminal introuvable", "Terminal nicht gefunden", "Terminal não encontrado"],
    "Compressione non riuscita": ["Compression failed", "Error al comprimir", "Échec de la compression", "Komprimierung fehlgeschlagen", "Falha na compressão"],
    "Creazione PDF non riuscita": ["Couldn’t create the PDF", "No se pudo crear el PDF", "Impossible de créer le PDF", "PDF konnte nicht erstellt werden", "Não foi possível criar o PDF"],
    "Esportazione non riuscita": ["Export failed", "Error al exportar", "Échec de l’exportation", "Export fehlgeschlagen", "Falha na exportação"],
    "Esportazione non supportata per questo file": ["Export isn’t supported for this file", "Exportación no compatible con este archivo", "Exportation non prise en charge pour ce fichier", "Export für diese Datei nicht unterstützt", "Exportação não suportada para este arquivo"],
    "Filtro non riuscito": ["Filter failed", "Error del filtro", "Échec du filtre", "Filter fehlgeschlagen", "Falha no filtro"],
    "Formato di destinazione non supportato": ["Unsupported output format", "Formato de destino no compatible", "Format de destination non pris en charge", "Zielformat nicht unterstützt", "Formato de destino não suportado"],
    "Formato non supportato": ["Unsupported format", "Formato no compatible", "Format non pris en charge", "Format nicht unterstützt", "Formato não suportado"],
    "Il PDF non contiene testo selezionabile (è una scansione?)": [
        "The PDF has no selectable text (is it a scan?)", "El PDF no contiene texto seleccionable (¿es un escaneo?)",
        "Le PDF ne contient pas de texte sélectionnable (est-ce un scan ?)", "Das PDF enthält keinen auswählbaren Text (ist es ein Scan?)",
        "O PDF não contém texto selecionável (é uma digitalização?)"],
    "Impossibile aprire %@": ["Can’t open %@", "No se puede abrir %@", "Impossible d’ouvrir %@", "%@ kann nicht geöffnet werden", "Não é possível abrir %@"],
    "Impossibile aprire il PDF": ["Can’t open the PDF", "No se puede abrir el PDF", "Impossible d’ouvrir le PDF", "Das PDF kann nicht geöffnet werden", "Não é possível abrir o PDF"],
    "Impossibile leggere l'immagine": ["Can’t read the image", "No se puede leer la imagen", "Impossible de lire l’image", "Bild kann nicht gelesen werden", "Não é possível ler a imagem"],
    "Impossibile leggere l'immagine %@": ["Can’t read the image %@", "No se puede leer la imagen %@", "Impossible de lire l’image %@", "Bild %@ kann nicht gelesen werden", "Não é possível ler a imagem %@"],
    "Nessun soggetto trovato nell'immagine": ["No subject found in the image", "No se encontró ningún sujeto en la imagen", "Aucun sujet trouvé dans l’image", "Kein Motiv im Bild gefunden", "Nenhum objeto encontrado na imagem"],
    "Scontorno non riuscito": ["Background removal failed", "No se pudo quitar el fondo", "Échec du détourage", "Freistellen fehlgeschlagen", "Falha ao remover o fundo"],
    "Scrittura PDF non riuscita": ["Couldn’t write the PDF", "No se pudo escribir el PDF", "Impossible d’écrire le PDF", "PDF konnte nicht geschrieben werden", "Não foi possível gravar o PDF"],
    "Scrittura dell'immagine non riuscita": ["Couldn’t write the image", "No se pudo escribir la imagen", "Impossible d’écrire l’image", "Bild konnte nicht geschrieben werden", "Não foi possível gravar a imagem"],
    "ffmpeg non trovato. Installalo con: brew install ffmpeg": [
        "ffmpeg not found. Install it with: brew install ffmpeg", "ffmpeg no encontrado. Instálalo con: brew install ffmpeg",
        "ffmpeg introuvable. Installez-le avec : brew install ffmpeg", "ffmpeg nicht gefunden. Installiere es mit: brew install ffmpeg",
        "ffmpeg não encontrado. Instale com: brew install ffmpeg"],
    "%@ ha restituito un errore: %@": ["%@ returned an error: %@", "%@ devolvió un error: %@", "%@ a renvoyé une erreur : %@", "%@ hat einen Fehler gemeldet: %@", "%@ retornou um erro: %@"],

    // File-name parts
    "Archivio": ["Archive", "Archivo", "Archive", "Archiv", "Arquivo"],
    "Immagini": ["Images", "Imágenes", "Images", "Bilder", "Imagens"],
    "PDF uniti": ["Merged PDF", "PDF unidos", "PDF fusionnés", "Zusammengefügte PDFs", "PDFs unidos"],
    "compresso": ["compressed", "comprimido", "compressé", "komprimiert", "comprimido"],
    "compressa": ["compressed", "comprimida", "compressée", "komprimiert", "comprimida"],
    "ruotata": ["rotated", "girada", "pivotée", "gedreht", "girada"],
    "ruotato": ["rotated", "girado", "pivoté", "gedreht", "girado"],
    "specchiata": ["flipped", "volteada", "miroir", "gespiegelt", "espelhada"],
    "b&n": ["b&w", "b/n", "n&b", "s/w", "p&b"],
    "normalizzato": ["normalized", "normalizado", "normalisé", "normalisiert", "normalizado"],
    "muto": ["muted", "sin audio", "muet", "stumm", "mudo"],
    "frame": ["frame", "fotograma", "image", "Standbild", "quadro"],
    "pagine": ["pages", "páginas", "pages", "Seiten", "páginas"],
    "pagina 1": ["page 1", "página 1", "page 1", "Seite 1", "página 1"],
    "senza metadati": ["no metadata", "sin metadatos", "sans métadonnées", "ohne Metadaten", "sem metadados"],
    "senza sfondo": ["no background", "sin fondo", "sans fond", "ohne Hintergrund", "sem fundo"],
    "senza silenzi": ["no silence", "sin silencios", "sans silences", "ohne Stille", "sem silêncios"],
    "convertito": ["converted", "convertido", "converti", "konvertiert", "convertido"],
]
