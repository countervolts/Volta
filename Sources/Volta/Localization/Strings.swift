import Foundation

enum LocKey: String, CaseIterable, Hashable, Sendable {
    // Onboarding / login
    case login_tagline
    case login_add_servers_later
    case login_sign_in_to            // "%@" = service name
    case login_username
    case login_password
    case login_connect
    case login_connecting
    case login_sign_in_with_plex
    case login_waiting_for_plex
    case login_plex_email
    case login_plex_password
    case login_try_demo

    // HTTP warning + shared actions
    case http_warning_title
    case http_warning_message
    case action_edit_server
    case action_continue
    case action_cancel

    // Login errors / status
    case error_unreachable
    case error_bad_credentials
    case error_plex_timeout
    case error_plex_failed
    case plex_finish_sign_in

    // Tab bar
    case tab_home
    case tab_library
    case tab_playlists
    case tab_stats
    case tab_search

    // Shared actions
    case action_ok
    case action_done
    case action_save
    case action_delete
    case action_clear
    case action_remove
    case action_set
    case action_logout
    case action_download
    case action_play
    case action_shuffle
    case action_play_next
    case action_play_last
    case action_add_to_queue
    case action_add_to_playlist
    case action_save_as_playlist
    case action_saving
    case action_favorite
    case action_unfavorite
    case action_love
    case action_unlove
    case action_dislike
    case action_remove_dislike
    case action_info
    case action_go_to_album
    case action_go_to_artist
    case action_view_credits
    case action_share
    case action_remove_download
    case action_view_stats
    case action_retry_connection

    // Home
    case home_offline
    case home_downloaded_music
    case home_downloaded_albums
    case home_downloaded_songs
    case home_picks_for_you
    case home_recently_played
    case home_recently_added
    case home_artists
    case home_more_like                  // "%@" = artist name
    case home_discover
    case home_nothing_here
    case home_empty_message
    case home_server_unreachable
    case home_server_unreachable_message
    case home_mix_badge
    case home_song_count                 // "%d" = song count
    case home_saving_mix                 // "%@" = mix title
    case home_saved_to                   // "%@" = playlist name
    case home_save_mix_failed
    case home_genre_mix_title            // "%@" = genre
    case home_genre_mix_subtitle         // "%@" = genre
    case home_artist_mix_title           // "%@" = artist name
    case home_artist_mix_subtitle        // "%@" = artist name
    case home_discovery_station
    case home_discovery_station_subtitle
    case home_heavy_rotation
    case home_heavy_rotation_subtitle

    // Media metadata / sheets
    case media_title
    case media_artist
    case media_album
    case media_songs
    case media_duration
    case media_plays
    case media_year
    case media_genre
    case media_added
    case media_label
    case media_bit_rate
    case media_sample_rate
    case media_bit_depth
    case media_format
    case media_file_type
    case media_file_size
    case media_play_count
    case media_path
    case song_info_title
    case album_stats_title

    // Settings / language
    case settings_title
    case settings_language
    case settings_search
    case language_picker_footer

    // Settings section headers
    case settings_section_playback
    case settings_section_audio
    case settings_section_streaming
    case settings_section_performance
    case settings_section_appearance
    case settings_section_notifications
    case settings_section_backups
    case settings_section_server
    case settings_section_storage
    case settings_section_about
    case settings_section_developer

    // Appearance section rows
    case appearance_theme
    case appearance_lossless_badge
    case appearance_live_artwork
    case appearance_stylized_cover
    case appearance_song_artwork_lists
    case appearance_dynamic_background
    case appearance_accent_color
    case appearance_hidden_albums
    case hidden_albums_none
    case hidden_albums_count              // "%d" = hidden album count
    case hidden_albums_sort
    case hidden_albums_sort_visible_first
    case hidden_albums_sort_hidden_first
    case hidden_albums_search
    case hidden_albums_hide_visible
    case hidden_albums_show_visible
    case hidden_albums_show_all
    case hidden_albums_empty
    case hidden_albums_no_matches
    case hidden_albums_no_server
    case artist_singles
    case theme_dark
    case theme_amoled
    case theme_light

    // Notifications / toasts
    case notif_added_to_favorites
    case notif_removed_from_favorites
    case notif_added_to_queue
    case notif_playing_next
    case notif_download_cancelled
    case notif_download_removed
    case notif_demo_no_downloads
    case notif_downloaded                 // "%@" = song title
    case notif_downloads_cleared
    case notif_evicted_old_download
    case notif_no_downloads_to_remove
    case notif_everything_downloaded
    case notif_downloading_n              // "%d" = song count
    case notif_couldnt_load               // "%@" = title
    case notif_couldnt_load_album
    case notif_couldnt_load_artist
    case notif_could_not_connect
    case notif_connection_saved
    case notif_connection_test_passed
    case notif_connection_test_failed
    case notif_invalid_server_url
    case notif_invalid_cellular_url
    case notif_home_refreshed
    case notif_artwork_cache_cleared
    case notif_local_artwork_deleted
    case notif_local_lyrics_cleared
    case notif_lyrics_up_to_date
    case notif_lyrics_download_stopped
    case notif_lyrics_download_complete
    case notif_logs_cleared
    case notif_logs_zip_ready
    case notif_logs_folder_fallback
    case notif_app_files_zip_ready
    case notif_settings_backup_ready
    case notif_settings_restored
    case notif_settings_restore_failed
    case notif_playlists_exported
    case notif_playlist_export_failed
    case notif_imported_playlists         // "%d" = count
    case notif_playlist_import_failed
    case notif_playlist_backups_updated
    case notif_playlist_restored
    case notif_playlist_restore_failed
    case notif_playlist_backup_deleted
    case notif_stats_exported
    case notif_stats_export_failed
    case notif_listening_stats_cleared
    case notif_restart_to_apply

    // Busy Settings labels
    case settings_autoplay
    case settings_infinite_play
    case settings_track_transition
    case settings_gapless
    case settings_shuffle_default
    case settings_artwork_zoom
    case settings_resume_interruption
    case settings_equalizer
    case settings_volume_normalization
    case settings_mono_audio
    case settings_spatial_widener
    case settings_wifi_quality
    case settings_cellular_quality
    case settings_download_quality
    case settings_transcoding_format
    case settings_download_mode
    case settings_download_speed_limit
    case settings_download_storage_cap
    case settings_auto_evict
}

enum Strings {
    // English is the fallback when a translation is missing.
    private static func tr(
        en: String, es: String, fr: String, de: String, pt: String, it: String,
        nl: String, ru: String, pl: String, tr: String, sv: String, nb: String,
        da: String, fi: String, zh: String, ja: String, ko: String
    ) -> [AppLanguage: String] {
        [
            .english: en, .spanish: es, .french: fr, .german: de,
            .portuguese: pt, .italian: it, .dutch: nl, .russian: ru,
            .polish: pl, .turkish: tr, .swedish: sv, .norwegian: nb,
            .danish: da, .finnish: fi, .chinese: zh, .japanese: ja, .korean: ko,
        ]
    }

    static let table: [LocKey: [AppLanguage: String]] = [
        .login_tagline: [
            .english: "Choose your music server to get started",
            .spanish: "Elige tu servidor de música para empezar",
            .french: "Choisissez votre serveur de musique pour commencer",
            .german: "Wähle deinen Musikserver, um zu starten",
            .portuguese: "Escolha o seu servidor de música para começar",
            .italian: "Scegli il tuo server musicale per iniziare",
            .dutch: "Kies je muziekserver om te beginnen",
            .russian: "Выберите музыкальный сервер, чтобы начать",
            .polish: "Wybierz serwer muzyczny, aby rozpocząć",
            .turkish: "Başlamak için müzik sunucunu seç",
            .swedish: "Välj din musikserver för att komma igång",
            .norwegian: "Velg musikkserveren din for å komme i gang",
            .danish: "Vælg din musikserver for at komme i gang",
            .finnish: "Valitse musiikkipalvelin aloittaaksesi",
            .chinese: "选择你的音乐服务器以开始",
            .japanese: "音楽サーバーを選んで始めましょう",
            .korean: "시작하려면 음악 서버를 선택하세요",
        ],
        .login_add_servers_later: [
            .english: "You can add more servers later in Settings.",
            .spanish: "Puedes añadir más servidores luego en Ajustes.",
            .french: "Vous pourrez ajouter d'autres serveurs plus tard dans les Réglages.",
            .german: "Weitere Server kannst du später in den Einstellungen hinzufügen.",
            .portuguese: "Pode adicionar mais servidores depois nas Definições.",
            .italian: "Puoi aggiungere altri server in seguito nelle Impostazioni.",
            .dutch: "Je kunt later meer servers toevoegen in Instellingen.",
            .russian: "Дополнительные серверы можно добавить позже в настройках.",
            .polish: "Więcej serwerów możesz dodać później w Ustawieniach.",
            .turkish: "Daha fazla sunucuyu sonra Ayarlar'dan ekleyebilirsin.",
            .swedish: "Du kan lägga till fler servrar senare i Inställningar.",
            .norwegian: "Du kan legge til flere servere senere i Innstillinger.",
            .danish: "Du kan tilføje flere servere senere i Indstillinger.",
            .finnish: "Voit lisätä lisää palvelimia myöhemmin asetuksista.",
            .chinese: "你可以稍后在“设置”中添加更多服务器。",
            .japanese: "サーバーは後で設定から追加できます。",
            .korean: "나중에 설정에서 서버를 더 추가할 수 있습니다.",
        ],
        .login_sign_in_to: [
            .english: "Sign in to %@",
            .spanish: "Inicia sesión en %@",
            .french: "Connexion à %@",
            .german: "Bei %@ anmelden",
            .portuguese: "Iniciar sessão em %@",
            .italian: "Accedi a %@",
            .dutch: "Inloggen bij %@",
            .russian: "Войти в %@",
            .polish: "Zaloguj się do %@",
            .turkish: "Giriş yap: %@",
            .swedish: "Logga in på %@",
            .norwegian: "Logg på %@",
            .danish: "Log ind på %@",
            .finnish: "Kirjaudu palveluun %@",
            .chinese: "登录到 %@",
            .japanese: "%@ にサインイン",
            .korean: "%@에 로그인",
        ],
        .login_username: [
            .english: "Username",
            .spanish: "Usuario",
            .french: "Nom d'utilisateur",
            .german: "Benutzername",
            .portuguese: "Utilizador",
            .italian: "Nome utente",
            .dutch: "Gebruikersnaam",
            .russian: "Имя пользователя",
            .polish: "Nazwa użytkownika",
            .turkish: "Kullanıcı adı",
            .swedish: "Användarnamn",
            .norwegian: "Brukernavn",
            .danish: "Brugernavn",
            .finnish: "Käyttäjänimi",
            .chinese: "用户名",
            .japanese: "ユーザー名",
            .korean: "사용자 이름",
        ],
        .login_password: [
            .english: "Password",
            .spanish: "Contraseña",
            .french: "Mot de passe",
            .german: "Passwort",
            .portuguese: "Palavra-passe",
            .italian: "Password",
            .dutch: "Wachtwoord",
            .russian: "Пароль",
            .polish: "Hasło",
            .turkish: "Parola",
            .swedish: "Lösenord",
            .norwegian: "Passord",
            .danish: "Adgangskode",
            .finnish: "Salasana",
            .chinese: "密码",
            .japanese: "パスワード",
            .korean: "비밀번호",
        ],
        .login_connect: [
            .english: "Connect",
            .spanish: "Conectar",
            .french: "Se connecter",
            .german: "Verbinden",
            .portuguese: "Ligar",
            .italian: "Connetti",
            .dutch: "Verbinden",
            .russian: "Подключиться",
            .polish: "Połącz",
            .turkish: "Bağlan",
            .swedish: "Anslut",
            .norwegian: "Koble til",
            .danish: "Forbind",
            .finnish: "Yhdistä",
            .chinese: "连接",
            .japanese: "接続",
            .korean: "연결",
        ],
        .login_connecting: [
            .english: "Connecting",
            .spanish: "Conectando",
            .french: "Connexion…",
            .german: "Verbinden…",
            .portuguese: "A ligar…",
            .italian: "Connessione…",
            .dutch: "Verbinden…",
            .russian: "Подключение…",
            .polish: "Łączenie…",
            .turkish: "Bağlanıyor…",
            .swedish: "Ansluter…",
            .norwegian: "Kobler til…",
            .danish: "Forbinder…",
            .finnish: "Yhdistetään…",
            .chinese: "正在连接…",
            .japanese: "接続中…",
            .korean: "연결 중…",
        ],
        .login_sign_in_with_plex: [
            .english: "Sign in with Plex",
            .spanish: "Iniciar sesión con Plex",
            .french: "Se connecter avec Plex",
            .german: "Mit Plex anmelden",
            .portuguese: "Iniciar sessão com Plex",
            .italian: "Accedi con Plex",
            .dutch: "Inloggen met Plex",
            .russian: "Войти через Plex",
            .polish: "Zaloguj się przez Plex",
            .turkish: "Plex ile giriş yap",
            .swedish: "Logga in med Plex",
            .norwegian: "Logg på med Plex",
            .danish: "Log ind med Plex",
            .finnish: "Kirjaudu Plexillä",
            .chinese: "使用 Plex 登录",
            .japanese: "Plex でサインイン",
            .korean: "Plex로 로그인",
        ],
        .login_waiting_for_plex: [
            .english: "Waiting for Plex",
            .spanish: "Esperando a Plex",
            .french: "En attente de Plex",
            .german: "Warte auf Plex",
            .portuguese: "À espera do Plex",
            .italian: "In attesa di Plex",
            .dutch: "Wachten op Plex",
            .russian: "Ожидание Plex",
            .polish: "Oczekiwanie na Plex",
            .turkish: "Plex bekleniyor",
            .swedish: "Väntar på Plex",
            .norwegian: "Venter på Plex",
            .danish: "Venter på Plex",
            .finnish: "Odotetaan Plexiä",
            .chinese: "正在等待 Plex",
            .japanese: "Plex を待っています",
            .korean: "Plex 대기 중",
        ],
        .login_plex_email: [
            .english: "Plex account email",
            .spanish: "Correo de la cuenta de Plex",
            .french: "E-mail du compte Plex",
            .german: "E-Mail des Plex-Kontos",
            .portuguese: "E-mail da conta Plex",
            .italian: "Email dell'account Plex",
            .dutch: "E-mail van Plex-account",
            .russian: "Эл. почта аккаунта Plex",
            .polish: "E-mail konta Plex",
            .turkish: "Plex hesabı e-postası",
            .swedish: "E-post för Plex-konto",
            .norwegian: "E-post for Plex-konto",
            .danish: "E-mail til Plex-konto",
            .finnish: "Plex-tilin sähköposti",
            .chinese: "Plex 账户邮箱",
            .japanese: "Plex アカウントのメール",
            .korean: "Plex 계정 이메일",
        ],
        .login_plex_password: [
            .english: "Password or Plex token",
            .spanish: "Contraseña o token de Plex",
            .french: "Mot de passe ou jeton Plex",
            .german: "Passwort oder Plex-Token",
            .portuguese: "Palavra-passe ou token Plex",
            .italian: "Password o token Plex",
            .dutch: "Wachtwoord of Plex-token",
            .russian: "Пароль или токен Plex",
            .polish: "Hasło lub token Plex",
            .turkish: "Parola veya Plex jetonu",
            .swedish: "Lösenord eller Plex-token",
            .norwegian: "Passord eller Plex-token",
            .danish: "Adgangskode eller Plex-token",
            .finnish: "Salasana tai Plex-tunnus",
            .chinese: "密码或 Plex 令牌",
            .japanese: "パスワードまたは Plex トークン",
            .korean: "비밀번호 또는 Plex 토큰",
        ],
        .login_try_demo: [
            .english: "Try the demo server",
            .spanish: "Prueba el servidor de demostración",
            .french: "Essayer le serveur de démo",
            .german: "Demo-Server ausprobieren",
            .portuguese: "Experimentar o servidor de demonstração",
            .italian: "Prova il server demo",
            .dutch: "Probeer de demoserver",
            .russian: "Попробовать демо-сервер",
            .polish: "Wypróbuj serwer demonstracyjny",
            .turkish: "Demo sunucusunu deneyin",
            .swedish: "Prova demoservern",
            .norwegian: "Prøv demoserveren",
            .danish: "Prøv demoserveren",
            .finnish: "Kokeile demopalvelinta",
            .chinese: "试用演示服务器",
            .japanese: "デモサーバーを試す",
            .korean: "데모 서버 사용해 보기",
        ],
        .http_warning_title: [
            .english: "HTTP is not secure",
            .spanish: "HTTP no es seguro",
            .french: "HTTP n'est pas sécurisé",
            .german: "HTTP ist nicht sicher",
            .portuguese: "HTTP não é seguro",
            .italian: "HTTP non è sicuro",
            .dutch: "HTTP is niet veilig",
            .russian: "HTTP небезопасен",
            .polish: "HTTP nie jest bezpieczny",
            .turkish: "HTTP güvenli değil",
            .swedish: "HTTP är inte säkert",
            .norwegian: "HTTP er ikke sikkert",
            .danish: "HTTP er ikke sikkert",
            .finnish: "HTTP ei ole turvallinen",
            .chinese: "HTTP 不安全",
            .japanese: "HTTP は安全ではありません",
            .korean: "HTTP는 안전하지 않습니다",
        ],
        .http_warning_message: [
            .english: "Your login and music traffic may be visible on this connection. Use HTTPS when possible.",
            .spanish: "Tu inicio de sesión y tu tráfico de música podrían ser visibles en esta conexión. Usa HTTPS cuando sea posible.",
            .french: "Vos identifiants et votre trafic musical peuvent être visibles sur cette connexion. Utilisez HTTPS si possible.",
            .german: "Deine Anmeldedaten und dein Musik-Datenverkehr könnten auf dieser Verbindung sichtbar sein. Verwende nach Möglichkeit HTTPS.",
            .portuguese: "As suas credenciais e o tráfego de música podem ficar visíveis nesta ligação. Use HTTPS sempre que possível.",
            .italian: "Le tue credenziali e il traffico musicale potrebbero essere visibili su questa connessione. Usa HTTPS quando possibile.",
            .dutch: "Je inloggegevens en muziekverkeer kunnen zichtbaar zijn op deze verbinding. Gebruik HTTPS waar mogelijk.",
            .russian: "Ваши учётные данные и музыкальный трафик могут быть видны на этом соединении. По возможности используйте HTTPS.",
            .polish: "Twoje dane logowania i ruch muzyczny mogą być widoczne na tym połączeniu. W miarę możliwości używaj HTTPS.",
            .turkish: "Giriş bilgilerin ve müzik trafiğin bu bağlantıda görünür olabilir. Mümkün olduğunda HTTPS kullan.",
            .swedish: "Dina inloggningsuppgifter och musiktrafik kan vara synliga på den här anslutningen. Använd HTTPS när det är möjligt.",
            .norwegian: "Innloggingen og musikktrafikken din kan være synlig på denne tilkoblingen. Bruk HTTPS når det er mulig.",
            .danish: "Dine loginoplysninger og musiktrafik kan være synlige på denne forbindelse. Brug HTTPS når det er muligt.",
            .finnish: "Kirjautumistietosi ja musiikkiliikenteesi voivat näkyä tässä yhteydessä. Käytä HTTPS:ää, kun mahdollista.",
            .chinese: "在此连接上，你的登录信息和音乐流量可能会被看到。请尽量使用 HTTPS。",
            .japanese: "この接続ではログイン情報や音楽の通信が見られる可能性があります。可能な場合は HTTPS を使用してください。",
            .korean: "이 연결에서는 로그인 정보와 음악 트래픽이 노출될 수 있습니다. 가능하면 HTTPS를 사용하세요.",
        ],
        .action_edit_server: [
            .english: "Edit Server",
            .spanish: "Editar servidor",
            .french: "Modifier le serveur",
            .german: "Server bearbeiten",
            .portuguese: "Editar servidor",
            .italian: "Modifica server",
            .dutch: "Server bewerken",
            .russian: "Изменить сервер",
            .polish: "Edytuj serwer",
            .turkish: "Sunucuyu düzenle",
            .swedish: "Redigera server",
            .norwegian: "Rediger server",
            .danish: "Rediger server",
            .finnish: "Muokkaa palvelinta",
            .chinese: "编辑服务器",
            .japanese: "サーバーを編集",
            .korean: "서버 편집",
        ],
        .action_continue: [
            .english: "Continue",
            .spanish: "Continuar",
            .french: "Continuer",
            .german: "Fortfahren",
            .portuguese: "Continuar",
            .italian: "Continua",
            .dutch: "Doorgaan",
            .russian: "Продолжить",
            .polish: "Kontynuuj",
            .turkish: "Devam et",
            .swedish: "Fortsätt",
            .norwegian: "Fortsett",
            .danish: "Fortsæt",
            .finnish: "Jatka",
            .chinese: "继续",
            .japanese: "続ける",
            .korean: "계속",
        ],
        .action_cancel: [
            .english: "Cancel",
            .spanish: "Cancelar",
            .french: "Annuler",
            .german: "Abbrechen",
            .portuguese: "Cancelar",
            .italian: "Annulla",
            .dutch: "Annuleren",
            .russian: "Отмена",
            .polish: "Anuluj",
            .turkish: "İptal",
            .swedish: "Avbryt",
            .norwegian: "Avbryt",
            .danish: "Annuller",
            .finnish: "Peruuta",
            .chinese: "取消",
            .japanese: "キャンセル",
            .korean: "취소",
        ],
        .error_unreachable: [
            .english: "Could not reach the server.",
            .spanish: "No se pudo conectar con el servidor.",
            .french: "Impossible de joindre le serveur.",
            .german: "Server konnte nicht erreicht werden.",
            .portuguese: "Não foi possível contactar o servidor.",
            .italian: "Impossibile raggiungere il server.",
            .dutch: "Kan de server niet bereiken.",
            .russian: "Не удалось подключиться к серверу.",
            .polish: "Nie można połączyć się z serwerem.",
            .turkish: "Sunucuya ulaşılamadı.",
            .swedish: "Det gick inte att nå servern.",
            .norwegian: "Kunne ikke nå serveren.",
            .danish: "Kunne ikke nå serveren.",
            .finnish: "Palvelimeen ei saatu yhteyttä.",
            .chinese: "无法连接到服务器。",
            .japanese: "サーバーに接続できませんでした。",
            .korean: "서버에 연결할 수 없습니다.",
        ],
        .error_bad_credentials: [
            .english: "Incorrect username or password.",
            .spanish: "Usuario o contraseña incorrectos.",
            .french: "Nom d'utilisateur ou mot de passe incorrect.",
            .german: "Benutzername oder Passwort ist falsch.",
            .portuguese: "Utilizador ou palavra-passe incorretos.",
            .italian: "Nome utente o password non corretti.",
            .dutch: "Onjuiste gebruikersnaam of wachtwoord.",
            .russian: "Неверное имя пользователя или пароль.",
            .polish: "Nieprawidłowa nazwa użytkownika lub hasło.",
            .turkish: "Kullanıcı adı veya parola hatalı.",
            .swedish: "Fel användarnamn eller lösenord.",
            .norwegian: "Feil brukernavn eller passord.",
            .danish: "Forkert brugernavn eller adgangskode.",
            .finnish: "Väärä käyttäjänimi tai salasana.",
            .chinese: "用户名或密码不正确。",
            .japanese: "ユーザー名またはパスワードが正しくありません。",
            .korean: "사용자 이름 또는 비밀번호가 올바르지 않습니다.",
        ],
        .error_plex_timeout: [
            .english: "Plex sign-in timed out.",
            .spanish: "Se agotó el tiempo de inicio de sesión con Plex.",
            .french: "Délai de connexion à Plex dépassé.",
            .german: "Zeitüberschreitung bei der Plex-Anmeldung.",
            .portuguese: "O início de sessão com Plex expirou.",
            .italian: "Timeout dell'accesso a Plex.",
            .dutch: "Inloggen bij Plex is verlopen.",
            .russian: "Время входа через Plex истекло.",
            .polish: "Upłynął limit czasu logowania Plex.",
            .turkish: "Plex girişi zaman aşımına uğradı.",
            .swedish: "Plex-inloggningen tog för lång tid.",
            .norwegian: "Plex-innloggingen ble tidsavbrutt.",
            .danish: "Plex-login fik timeout.",
            .finnish: "Plex-kirjautuminen aikakatkaistiin.",
            .chinese: "Plex 登录超时。",
            .japanese: "Plex のサインインがタイムアウトしました。",
            .korean: "Plex 로그인 시간이 초과되었습니다.",
        ],
        .error_plex_failed: [
            .english: "Could not finish Plex sign-in.",
            .spanish: "No se pudo completar el inicio de sesión con Plex.",
            .french: "Impossible de terminer la connexion à Plex.",
            .german: "Plex-Anmeldung konnte nicht abgeschlossen werden.",
            .portuguese: "Não foi possível concluir o início de sessão com Plex.",
            .italian: "Impossibile completare l'accesso a Plex.",
            .dutch: "Kan het inloggen bij Plex niet voltooien.",
            .russian: "Не удалось завершить вход через Plex.",
            .polish: "Nie udało się zakończyć logowania Plex.",
            .turkish: "Plex girişi tamamlanamadı.",
            .swedish: "Det gick inte att slutföra Plex-inloggningen.",
            .norwegian: "Kunne ikke fullføre Plex-innloggingen.",
            .danish: "Kunne ikke fuldføre Plex-login.",
            .finnish: "Plex-kirjautumista ei voitu viimeistellä.",
            .chinese: "无法完成 Plex 登录。",
            .japanese: "Plex のサインインを完了できませんでした。",
            .korean: "Plex 로그인을 완료할 수 없습니다.",
        ],
        .plex_finish_sign_in: [
            .english: "Finish signing in with Plex",
            .spanish: "Termina de iniciar sesión con Plex",
            .french: "Terminez la connexion avec Plex",
            .german: "Schließe die Anmeldung mit Plex ab",
            .portuguese: "Conclua o início de sessão com Plex",
            .italian: "Completa l'accesso con Plex",
            .dutch: "Voltooi het inloggen met Plex",
            .russian: "Завершите вход через Plex",
            .polish: "Dokończ logowanie przez Plex",
            .turkish: "Plex ile girişi tamamla",
            .swedish: "Slutför inloggningen med Plex",
            .norwegian: "Fullfør innloggingen med Plex",
            .danish: "Fuldfør login med Plex",
            .finnish: "Viimeistele kirjautuminen Plexillä",
            .chinese: "完成 Plex 登录",
            .japanese: "Plex でのサインインを完了してください",
            .korean: "Plex 로그인을 완료하세요",
        ],
        .tab_home: [
            .english: "Home", .spanish: "Inicio", .french: "Accueil", .german: "Start",
            .portuguese: "Início", .italian: "Home", .dutch: "Start", .russian: "Главная",
            .polish: "Główna", .turkish: "Ana sayfa", .swedish: "Hem", .norwegian: "Hjem",
            .danish: "Hjem", .finnish: "Koti", .chinese: "主页", .japanese: "ホーム", .korean: "홈",
        ],
        .tab_library: [
            .english: "Library", .spanish: "Biblioteca", .french: "Bibliothèque", .german: "Mediathek",
            .portuguese: "Biblioteca", .italian: "Libreria", .dutch: "Bibliotheek", .russian: "Медиатека",
            .polish: "Biblioteka", .turkish: "Kitaplık", .swedish: "Bibliotek", .norwegian: "Bibliotek",
            .danish: "Bibliotek", .finnish: "Kirjasto", .chinese: "音乐库", .japanese: "ライブラリ", .korean: "보관함",
        ],
        .tab_playlists: [
            .english: "Playlists", .spanish: "Listas", .french: "Playlists", .german: "Playlists",
            .portuguese: "Listas", .italian: "Playlist", .dutch: "Afspeellijsten", .russian: "Плейлисты",
            .polish: "Playlisty", .turkish: "Çalma listeleri", .swedish: "Spellistor", .norwegian: "Spillelister",
            .danish: "Spillelister", .finnish: "Soittolistat", .chinese: "播放列表", .japanese: "プレイリスト", .korean: "재생목록",
        ],
        .tab_stats: [
            .english: "Stats", .spanish: "Estadísticas", .french: "Stats", .german: "Statistik",
            .portuguese: "Estatísticas", .italian: "Statistiche", .dutch: "Statistieken", .russian: "Статистика",
            .polish: "Statystyki", .turkish: "İstatistik", .swedish: "Statistik", .norwegian: "Statistikk",
            .danish: "Statistik", .finnish: "Tilastot", .chinese: "统计", .japanese: "統計", .korean: "통계",
        ],
        .tab_search: [
            .english: "Search", .spanish: "Buscar", .french: "Rechercher", .german: "Suche",
            .portuguese: "Pesquisar", .italian: "Cerca", .dutch: "Zoeken", .russian: "Поиск",
            .polish: "Szukaj", .turkish: "Ara", .swedish: "Sök", .norwegian: "Søk",
            .danish: "Søg", .finnish: "Haku", .chinese: "搜索", .japanese: "検索", .korean: "검색",
        ],
        .action_ok: [
            .english: "OK", .spanish: "OK", .french: "OK", .german: "OK",
            .portuguese: "OK", .italian: "OK", .dutch: "OK", .russian: "ОК",
            .polish: "OK", .turkish: "Tamam", .swedish: "OK", .norwegian: "OK",
            .danish: "OK", .finnish: "OK", .chinese: "确定", .japanese: "OK", .korean: "확인",
        ],
        .action_done: [
            .english: "Done", .spanish: "Listo", .french: "Terminé", .german: "Fertig",
            .portuguese: "Concluído", .italian: "Fine", .dutch: "Klaar", .russian: "Готово",
            .polish: "Gotowe", .turkish: "Bitti", .swedish: "Klar", .norwegian: "Ferdig",
            .danish: "Færdig", .finnish: "Valmis", .chinese: "完成", .japanese: "完了", .korean: "완료",
        ],
        .action_save: [
            .english: "Save", .spanish: "Guardar", .french: "Enregistrer", .german: "Speichern",
            .portuguese: "Guardar", .italian: "Salva", .dutch: "Opslaan", .russian: "Сохранить",
            .polish: "Zapisz", .turkish: "Kaydet", .swedish: "Spara", .norwegian: "Lagre",
            .danish: "Gem", .finnish: "Tallenna", .chinese: "保存", .japanese: "保存", .korean: "저장",
        ],
        .action_delete: [
            .english: "Delete", .spanish: "Eliminar", .french: "Supprimer", .german: "Löschen",
            .portuguese: "Eliminar", .italian: "Elimina", .dutch: "Verwijderen", .russian: "Удалить",
            .polish: "Usuń", .turkish: "Sil", .swedish: "Radera", .norwegian: "Slett",
            .danish: "Slet", .finnish: "Poista", .chinese: "删除", .japanese: "削除", .korean: "삭제",
        ],
        .action_clear: [
            .english: "Clear", .spanish: "Borrar", .french: "Effacer", .german: "Löschen",
            .portuguese: "Limpar", .italian: "Cancella", .dutch: "Wissen", .russian: "Очистить",
            .polish: "Wyczyść", .turkish: "Temizle", .swedish: "Rensa", .norwegian: "Tøm",
            .danish: "Ryd", .finnish: "Tyhjennä", .chinese: "清除", .japanese: "消去", .korean: "지우기",
        ],
        .action_remove: [
            .english: "Remove", .spanish: "Quitar", .french: "Retirer", .german: "Entfernen",
            .portuguese: "Remover", .italian: "Rimuovi", .dutch: "Verwijderen", .russian: "Убрать",
            .polish: "Usuń", .turkish: "Kaldır", .swedish: "Ta bort", .norwegian: "Fjern",
            .danish: "Fjern", .finnish: "Poista", .chinese: "移除", .japanese: "削除", .korean: "제거",
        ],
        .action_set: [
            .english: "Set", .spanish: "Establecer", .french: "Définir", .german: "Festlegen",
            .portuguese: "Definir", .italian: "Imposta", .dutch: "Instellen", .russian: "Задать",
            .polish: "Ustaw", .turkish: "Ayarla", .swedish: "Ange", .norwegian: "Angi",
            .danish: "Indstil", .finnish: "Aseta", .chinese: "设置", .japanese: "設定", .korean: "설정",
        ],
        .action_logout: [
            .english: "Log Out", .spanish: "Cerrar sesión", .french: "Se déconnecter", .german: "Abmelden",
            .portuguese: "Terminar sessão", .italian: "Esci", .dutch: "Uitloggen", .russian: "Выйти",
            .polish: "Wyloguj", .turkish: "Çıkış yap", .swedish: "Logga ut", .norwegian: "Logg ut",
            .danish: "Log ud", .finnish: "Kirjaudu ulos", .chinese: "退出登录", .japanese: "ログアウト", .korean: "로그아웃",
        ],
        .action_download: [
            .english: "Download", .spanish: "Descargar", .french: "Télécharger", .german: "Laden",
            .portuguese: "Transferir", .italian: "Scarica", .dutch: "Downloaden", .russian: "Скачать",
            .polish: "Pobierz", .turkish: "İndir", .swedish: "Ladda ner", .norwegian: "Last ned",
            .danish: "Hent", .finnish: "Lataa", .chinese: "下载", .japanese: "ダウンロード", .korean: "다운로드",
        ],
        .action_play: tr(
            en: "Play", es: "Reproducir", fr: "Lire", de: "Abspielen", pt: "Reproduzir", it: "Riproduci",
            nl: "Afspelen", ru: "Воспроизвести", pl: "Odtwórz", tr: "Çal", sv: "Spela", nb: "Spill",
            da: "Afspil", fi: "Toista", zh: "播放", ja: "再生", ko: "재생"
        ),
        .action_shuffle: tr(
            en: "Shuffle", es: "Aleatorio", fr: "Aléatoire", de: "Zufällig", pt: "Aleatório", it: "Casuale",
            nl: "Shuffle", ru: "Перемешать", pl: "Losowo", tr: "Karıştır", sv: "Blanda", nb: "Bland",
            da: "Bland", fi: "Sekoita", zh: "随机播放", ja: "シャッフル", ko: "셔플"
        ),
        .action_play_next: tr(
            en: "Play Next", es: "Reproducir después", fr: "Lire ensuite", de: "Als Nächstes", pt: "Reproduzir a seguir", it: "Riproduci dopo",
            nl: "Speel hierna", ru: "Далее", pl: "Odtwórz następne", tr: "Sonra çal", sv: "Spela härnäst", nb: "Spill neste",
            da: "Afspil næste", fi: "Toista seuraavaksi", zh: "下一首播放", ja: "次に再生", ko: "다음에 재생"
        ),
        .action_play_last: tr(
            en: "Play Last", es: "Reproducir al final", fr: "Lire en dernier", de: "Zuletzt abspielen", pt: "Reproduzir por último", it: "Riproduci per ultimo",
            nl: "Speel als laatste", ru: "В конец очереди", pl: "Odtwórz na końcu", tr: "En son çal", sv: "Spela sist", nb: "Spill sist",
            da: "Afspil sidst", fi: "Toista viimeisenä", zh: "最后播放", ja: "最後に再生", ko: "마지막에 재생"
        ),
        .action_add_to_queue: tr(
            en: "Add to Queue", es: "Añadir a la cola", fr: "Ajouter à la file", de: "Zur Warteschlange", pt: "Adicionar à fila", it: "Aggiungi alla coda",
            nl: "Aan wachtrij toevoegen", ru: "Добавить в очередь", pl: "Dodaj do kolejki", tr: "Sıraya ekle", sv: "Lägg till i kön", nb: "Legg til i køen",
            da: "Føj til køen", fi: "Lisää jonoon", zh: "加入队列", ja: "キューに追加", ko: "대기열에 추가"
        ),
        .action_add_to_playlist: tr(
            en: "Add to Playlist", es: "Añadir a lista", fr: "Ajouter à une playlist", de: "Zur Playlist", pt: "Adicionar à lista", it: "Aggiungi a playlist",
            nl: "Aan afspeellijst toevoegen", ru: "Добавить в плейлист", pl: "Dodaj do playlisty", tr: "Listeye ekle", sv: "Lägg till i spellista", nb: "Legg til i spilleliste",
            da: "Føj til playliste", fi: "Lisää soittolistaan", zh: "加入播放列表", ja: "プレイリストに追加", ko: "재생목록에 추가"
        ),
        .action_save_as_playlist: tr(
            en: "Save as Playlist", es: "Guardar como lista", fr: "Enregistrer en playlist", de: "Als Playlist sichern", pt: "Guardar como lista", it: "Salva come playlist",
            nl: "Opslaan als afspeellijst", ru: "Сохранить как плейлист", pl: "Zapisz jako playlistę", tr: "Liste olarak kaydet", sv: "Spara som spellista", nb: "Lagre som spilleliste",
            da: "Gem som playliste", fi: "Tallenna soittolistaksi", zh: "存为播放列表", ja: "プレイリストとして保存", ko: "재생목록으로 저장"
        ),
        .action_saving: tr(
            en: "Saving...", es: "Guardando...", fr: "Enregistrement...", de: "Speichern...", pt: "A guardar...", it: "Salvataggio...",
            nl: "Opslaan...", ru: "Сохранение...", pl: "Zapisywanie...", tr: "Kaydediliyor...", sv: "Sparar...", nb: "Lagrer...",
            da: "Gemmer...", fi: "Tallennetaan...", zh: "正在保存...", ja: "保存中...", ko: "저장 중..."
        ),
        .action_favorite: tr(
            en: "Favorite", es: "Favorito", fr: "Favori", de: "Favorit", pt: "Favorito", it: "Preferito",
            nl: "Favoriet", ru: "В избранное", pl: "Ulubione", tr: "Favori", sv: "Favorit", nb: "Favoritt",
            da: "Favorit", fi: "Suosikki", zh: "收藏", ja: "お気に入り", ko: "즐겨찾기"
        ),
        .action_unfavorite: tr(
            en: "Unfavorite", es: "Quitar favorito", fr: "Retirer des favoris", de: "Favorit entfernen", pt: "Remover favorito", it: "Rimuovi preferito",
            nl: "Favoriet verwijderen", ru: "Убрать из избранного", pl: "Usuń z ulubionych", tr: "Favoriden çıkar", sv: "Ta bort favorit", nb: "Fjern favoritt",
            da: "Fjern favorit", fi: "Poista suosikki", zh: "取消收藏", ja: "お気に入り解除", ko: "즐겨찾기 해제"
        ),
        .action_love: tr(
            en: "Love", es: "Me gusta", fr: "J'aime", de: "Lieben", pt: "Adorar", it: "Mi piace",
            nl: "Leuk vinden", ru: "Нравится", pl: "Lubię", tr: "Beğen", sv: "Gilla", nb: "Lik",
            da: "Synes om", fi: "Tykkää", zh: "喜欢", ja: "ラブ", ko: "좋아요"
        ),
        .action_unlove: tr(
            en: "Unlove", es: "Quitar me gusta", fr: "Ne plus aimer", de: "Nicht mehr lieben", pt: "Remover gosto", it: "Non mi piace più",
            nl: "Niet meer leuk", ru: "Убрать отметку", pl: "Cofnij polubienie", tr: "Beğeniyi kaldır", sv: "Sluta gilla", nb: "Fjern liker",
            da: "Fjern synes om", fi: "Poista tykkäys", zh: "取消喜欢", ja: "ラブを解除", ko: "좋아요 취소"
        ),
        .action_dislike: tr(
            en: "Dislike", es: "No me gusta", fr: "Je n'aime pas", de: "Nicht mögen", pt: "Não gosto", it: "Non mi piace",
            nl: "Niet leuk", ru: "Не нравится", pl: "Nie lubię", tr: "Beğenme", sv: "Ogilla", nb: "Mislik",
            da: "Synes ikke om", fi: "En tykkää", zh: "不喜欢", ja: "低評価", ko: "싫어요"
        ),
        .action_remove_dislike: tr(
            en: "Remove Dislike", es: "Quitar no me gusta", fr: "Retirer le rejet", de: "Ablehnung entfernen", pt: "Remover não gosto", it: "Rimuovi non mi piace",
            nl: "Afkeer verwijderen", ru: "Убрать дизлайк", pl: "Usuń nie lubię", tr: "Beğenmeme kaldır", sv: "Ta bort ogilla", nb: "Fjern mislik",
            da: "Fjern synes ikke om", fi: "Poista en tykkää", zh: "取消不喜欢", ja: "低評価を解除", ko: "싫어요 취소"
        ),
        .action_info: tr(
            en: "Info", es: "Información", fr: "Infos", de: "Info", pt: "Info", it: "Info",
            nl: "Info", ru: "Сведения", pl: "Info", tr: "Bilgi", sv: "Info", nb: "Info",
            da: "Info", fi: "Tiedot", zh: "信息", ja: "情報", ko: "정보"
        ),
        .action_go_to_album: tr(
            en: "Go to Album", es: "Ir al álbum", fr: "Aller à l'album", de: "Zum Album", pt: "Ir para o álbum", it: "Vai all'album",
            nl: "Ga naar album", ru: "К альбому", pl: "Przejdź do albumu", tr: "Albüme git", sv: "Gå till album", nb: "Gå til album",
            da: "Gå til album", fi: "Siirry albumiin", zh: "前往专辑", ja: "アルバムへ移動", ko: "앨범으로 이동"
        ),
        .action_go_to_artist: tr(
            en: "Go to Artist", es: "Ir al artista", fr: "Aller à l'artiste", de: "Zum Künstler", pt: "Ir para o artista", it: "Vai all'artista",
            nl: "Ga naar artiest", ru: "К исполнителю", pl: "Przejdź do wykonawcy", tr: "Sanatçıya git", sv: "Gå till artist", nb: "Gå til artist",
            da: "Gå til kunstner", fi: "Siirry artistiin", zh: "前往艺人", ja: "アーティストへ移動", ko: "아티스트로 이동"
        ),
        .action_view_credits: tr(
            en: "View Credits", es: "Ver créditos", fr: "Voir les crédits", de: "Credits anzeigen", pt: "Ver créditos", it: "Vedi crediti",
            nl: "Credits bekijken", ru: "Показать кредиты", pl: "Pokaż autorów", tr: "Katkıları gör", sv: "Visa medverkande", nb: "Vis medvirkende",
            da: "Vis krediteringer", fi: "Näytä tekijät", zh: "查看制作名单", ja: "クレジットを表示", ko: "크레딧 보기"
        ),
        .action_share: tr(
            en: "Share", es: "Compartir", fr: "Partager", de: "Teilen", pt: "Partilhar", it: "Condividi",
            nl: "Delen", ru: "Поделиться", pl: "Udostępnij", tr: "Paylaş", sv: "Dela", nb: "Del",
            da: "Del", fi: "Jaa", zh: "分享", ja: "共有", ko: "공유"
        ),
        .action_remove_download: tr(
            en: "Remove Download", es: "Eliminar descarga", fr: "Supprimer le téléchargement", de: "Download entfernen", pt: "Remover transferência", it: "Rimuovi download",
            nl: "Download verwijderen", ru: "Удалить загрузку", pl: "Usuń pobranie", tr: "İndirmeyi kaldır", sv: "Ta bort nedladdning", nb: "Fjern nedlasting",
            da: "Fjern download", fi: "Poista lataus", zh: "移除下载", ja: "ダウンロードを削除", ko: "다운로드 제거"
        ),
        .action_view_stats: tr(
            en: "View Stats", es: "Ver estadísticas", fr: "Voir les stats", de: "Statistiken anzeigen", pt: "Ver estatísticas", it: "Vedi statistiche",
            nl: "Statistieken bekijken", ru: "Показать статистику", pl: "Pokaż statystyki", tr: "İstatistikleri gör", sv: "Visa statistik", nb: "Vis statistikk",
            da: "Vis statistik", fi: "Näytä tilastot", zh: "查看统计", ja: "統計を表示", ko: "통계 보기"
        ),
        .action_retry_connection: tr(
            en: "Retry Connection", es: "Reintentar conexión", fr: "Réessayer la connexion", de: "Verbindung erneut versuchen", pt: "Tentar ligação novamente", it: "Riprova connessione",
            nl: "Verbinding opnieuw proberen", ru: "Повторить подключение", pl: "Ponów połączenie", tr: "Bağlantıyı yeniden dene", sv: "Försök ansluta igen", nb: "Prøv tilkobling igjen",
            da: "Prøv forbindelse igen", fi: "Yritä yhteyttä uudelleen", zh: "重试连接", ja: "接続を再試行", ko: "연결 다시 시도"
        ),

        // Home
        .home_offline: tr(
            en: "Offline", es: "Sin conexión", fr: "Hors ligne", de: "Offline", pt: "Offline", it: "Offline",
            nl: "Offline", ru: "Офлайн", pl: "Offline", tr: "Çevrimdışı", sv: "Offline", nb: "Frakoblet",
            da: "Offline", fi: "Offline", zh: "离线", ja: "オフライン", ko: "오프라인"
        ),
        .home_downloaded_music: tr(
            en: "Your downloaded music", es: "Tu música descargada", fr: "Votre musique téléchargée", de: "Deine geladene Musik", pt: "A sua música transferida", it: "La tua musica scaricata",
            nl: "Je gedownloade muziek", ru: "Ваша загруженная музыка", pl: "Twoja pobrana muzyka", tr: "İndirilen müziğin", sv: "Din nedladdade musik", nb: "Din nedlastede musikk",
            da: "Din hentede musik", fi: "Ladattu musiikkisi", zh: "你下载的音乐", ja: "ダウンロード済みの音楽", ko: "다운로드한 음악"
        ),
        .home_downloaded_albums: tr(
            en: "Downloaded Albums", es: "Álbumes descargados", fr: "Albums téléchargés", de: "Geladene Alben", pt: "Álbuns transferidos", it: "Album scaricati",
            nl: "Gedownloade albums", ru: "Загруженные альбомы", pl: "Pobrane albumy", tr: "İndirilen albümler", sv: "Nedladdade album", nb: "Nedlastede album",
            da: "Hentede album", fi: "Ladatut albumit", zh: "已下载专辑", ja: "ダウンロード済みアルバム", ko: "다운로드한 앨범"
        ),
        .home_downloaded_songs: tr(
            en: "Downloaded Songs", es: "Canciones descargadas", fr: "Titres téléchargés", de: "Geladene Songs", pt: "Músicas transferidas", it: "Brani scaricati",
            nl: "Gedownloade nummers", ru: "Загруженные песни", pl: "Pobrane utwory", tr: "İndirilen şarkılar", sv: "Nedladdade låtar", nb: "Nedlastede låter",
            da: "Hentede sange", fi: "Ladatut kappaleet", zh: "已下载歌曲", ja: "ダウンロード済みの曲", ko: "다운로드한 곡"
        ),
        .home_picks_for_you: tr(
            en: "Picks for You", es: "Para ti", fr: "Sélection pour vous", de: "Für dich", pt: "Escolhas para si", it: "Scelte per te",
            nl: "Aanraders voor jou", ru: "Подборка для вас", pl: "Propozycje dla Ciebie", tr: "Senin için seçtiklerimiz", sv: "Tips för dig", nb: "Anbefalt for deg",
            da: "Anbefalet til dig", fi: "Sinulle valitut", zh: "为你推荐", ja: "あなたへのおすすめ", ko: "추천 항목"
        ),
        .home_recently_played: tr(
            en: "Recently Played", es: "Reproducido recientemente", fr: "Écouté récemment", de: "Zuletzt gespielt", pt: "Reproduzido recentemente", it: "Ascoltati di recente",
            nl: "Recent afgespeeld", ru: "Недавно прослушано", pl: "Ostatnio odtwarzane", tr: "Son çalınanlar", sv: "Nyligen spelat", nb: "Nylig spilt",
            da: "Afspillet for nylig", fi: "Viimeksi toistetut", zh: "最近播放", ja: "最近再生", ko: "최근 재생"
        ),
        .home_recently_added: tr(
            en: "Recently Added", es: "Añadido recientemente", fr: "Ajouté récemment", de: "Zuletzt hinzugefügt", pt: "Adicionado recentemente", it: "Aggiunti di recente",
            nl: "Recent toegevoegd", ru: "Недавно добавлено", pl: "Ostatnio dodane", tr: "Son eklenenler", sv: "Nyligen tillagt", nb: "Nylig lagt til",
            da: "Tilføjet for nylig", fi: "Viimeksi lisätyt", zh: "最近添加", ja: "最近追加", ko: "최근 추가"
        ),
        .home_artists: tr(
            en: "Artists", es: "Artistas", fr: "Artistes", de: "Künstler", pt: "Artistas", it: "Artisti",
            nl: "Artiesten", ru: "Исполнители", pl: "Wykonawcy", tr: "Sanatçılar", sv: "Artister", nb: "Artister",
            da: "Kunstnere", fi: "Artistit", zh: "艺人", ja: "アーティスト", ko: "아티스트"
        ),
        .home_more_like: tr(
            en: "More Like %@", es: "Más como %@", fr: "Plus comme %@", de: "Mehr wie %@", pt: "Mais como %@", it: "Altro come %@",
            nl: "Meer zoals %@", ru: "Похоже на %@", pl: "Więcej jak %@", tr: "%@ benzerleri", sv: "Mer som %@", nb: "Mer som %@",
            da: "Mere som %@", fi: "Lisää kuten %@", zh: "更多类似 %@", ja: "%@ に似た作品", ko: "%@ 비슷한 항목"
        ),
        .home_discover: tr(
            en: "Discover", es: "Descubrir", fr: "Découvrir", de: "Entdecken", pt: "Descobrir", it: "Scopri",
            nl: "Ontdekken", ru: "Открытия", pl: "Odkrywaj", tr: "Keşfet", sv: "Upptäck", nb: "Oppdag",
            da: "Opdag", fi: "Löydä", zh: "发现", ja: "見つける", ko: "발견"
        ),
        .home_nothing_here: tr(
            en: "Nothing here yet", es: "Aún no hay nada", fr: "Rien ici pour l'instant", de: "Noch nichts hier", pt: "Ainda não há nada", it: "Ancora niente qui",
            nl: "Nog niets hier", ru: "Здесь пока ничего", pl: "Jeszcze nic tu nie ma", tr: "Henüz bir şey yok", sv: "Inget här än", nb: "Ingenting her ennå",
            da: "Intet her endnu", fi: "Ei vielä mitään", zh: "这里还没有内容", ja: "まだ何もありません", ko: "아직 아무것도 없음"
        ),
        .home_empty_message: tr(
            en: "Your library looks empty or the server is unreachable.", es: "Tu biblioteca parece vacía o el servidor no responde.", fr: "Votre bibliothèque semble vide ou le serveur est inaccessible.", de: "Deine Mediathek ist leer oder der Server ist nicht erreichbar.", pt: "A biblioteca parece vazia ou o servidor está indisponível.", it: "La libreria sembra vuota o il server non è raggiungibile.",
            nl: "Je bibliotheek lijkt leeg of de server is onbereikbaar.", ru: "Медиатека пуста или сервер недоступен.", pl: "Biblioteka jest pusta albo serwer jest niedostępny.", tr: "Kitaplığın boş görünüyor veya sunucuya ulaşılamıyor.", sv: "Biblioteket verkar tomt eller servern kan inte nås.", nb: "Biblioteket ser tomt ut, eller serveren kan ikke nås.",
            da: "Biblioteket ser tomt ud, eller serveren kan ikke nås.", fi: "Kirjastosi näyttää tyhjältä tai palvelimeen ei saada yhteyttä.", zh: "你的音乐库似乎为空，或服务器无法访问。", ja: "ライブラリが空か、サーバーに接続できません。", ko: "보관함이 비었거나 서버에 연결할 수 없습니다."
        ),
        .home_server_unreachable: tr(
            en: "Server Unreachable", es: "Servidor inaccesible", fr: "Serveur inaccessible", de: "Server nicht erreichbar", pt: "Servidor indisponível", it: "Server non raggiungibile",
            nl: "Server onbereikbaar", ru: "Сервер недоступен", pl: "Serwer niedostępny", tr: "Sunucuya ulaşılamıyor", sv: "Servern kan inte nås", nb: "Serveren kan ikke nås",
            da: "Serveren kan ikke nås", fi: "Palvelimeen ei saada yhteyttä", zh: "服务器无法访问", ja: "サーバーに接続できません", ko: "서버에 연결할 수 없음"
        ),
        .home_server_unreachable_message: tr(
            en: "Picks for You needs the server. Try reconnecting, or listen to downloaded music from the Library tab.", es: "Para ti necesita el servidor. Intenta reconectar o escucha música descargada desde la pestaña Biblioteca.", fr: "La sélection a besoin du serveur. Réessayez la connexion ou écoutez la musique téléchargée dans Bibliothèque.", de: "Für dich braucht den Server. Verbinde dich erneut oder höre geladene Musik in der Mediathek.", pt: "As escolhas precisam do servidor. Tente ligar novamente ou ouça música transferida na Biblioteca.", it: "Le scelte richiedono il server. Riprova la connessione o ascolta musica scaricata dalla Libreria.",
            nl: "Aanraders hebben de server nodig. Probeer opnieuw te verbinden of luister naar downloads in Bibliotheek.", ru: "Для подборок нужен сервер. Подключитесь снова или слушайте загруженную музыку в медиатеке.", pl: "Propozycje wymagają serwera. Połącz ponownie albo słuchaj pobranej muzyki w Bibliotece.", tr: "Seçkiler için sunucu gerekir. Yeniden bağlanmayı dene veya indirilen müziği Kitaplık'tan dinle.", sv: "Tipsen behöver servern. Försök ansluta igen eller lyssna på nedladdad musik i Bibliotek.", nb: "Anbefalinger trenger serveren. Prøv å koble til igjen, eller lytt til nedlastet musikk i Bibliotek.",
            da: "Anbefalinger kræver serveren. Prøv at forbinde igen, eller lyt til hentet musik i Bibliotek.", fi: "Suositukset tarvitsevat palvelimen. Yritä yhdistää uudelleen tai kuuntele ladattua musiikkia Kirjastosta.", zh: "推荐内容需要服务器。请尝试重新连接，或在音乐库中收听已下载音乐。", ja: "おすすめにはサーバーが必要です。再接続するか、ライブラリでダウンロード済みの音楽を聴いてください。", ko: "추천 항목에는 서버가 필요합니다. 다시 연결하거나 보관함에서 다운로드한 음악을 들어보세요."
        ),
        .home_mix_badge: tr(
            en: "MIX", es: "MIX", fr: "MIX", de: "MIX", pt: "MIX", it: "MIX",
            nl: "MIX", ru: "МИКС", pl: "MIX", tr: "MIX", sv: "MIX", nb: "MIX",
            da: "MIX", fi: "MIX", zh: "混音", ja: "ミックス", ko: "믹스"
        ),
        .home_song_count: tr(
            en: "%d songs", es: "%d canciones", fr: "%d titres", de: "%d Songs", pt: "%d músicas", it: "%d brani",
            nl: "%d nummers", ru: "%d песен", pl: "%d utworów", tr: "%d şarkı", sv: "%d låtar", nb: "%d låter",
            da: "%d sange", fi: "%d kappaletta", zh: "%d 首歌曲", ja: "%d 曲", ko: "%d곡"
        ),
        .home_saving_mix: tr(
            en: "Saving %@", es: "Guardando %@", fr: "Enregistrement de %@", de: "%@ wird gespeichert", pt: "A guardar %@", it: "Salvataggio di %@",
            nl: "%@ opslaan", ru: "Сохранение %@", pl: "Zapisywanie %@", tr: "%@ kaydediliyor", sv: "Sparar %@", nb: "Lagrer %@",
            da: "Gemmer %@", fi: "Tallennetaan %@", zh: "正在保存 %@", ja: "%@ を保存中", ko: "%@ 저장 중"
        ),
        .home_saved_to: tr(
            en: "Saved to %@", es: "Guardado en %@", fr: "Enregistré dans %@", de: "Gespeichert in %@", pt: "Guardado em %@", it: "Salvato in %@",
            nl: "Opgeslagen in %@", ru: "Сохранено в %@", pl: "Zapisano w %@", tr: "%@ içine kaydedildi", sv: "Sparat i %@", nb: "Lagret i %@",
            da: "Gemt i %@", fi: "Tallennettu kohteeseen %@", zh: "已保存到 %@", ja: "%@ に保存しました", ko: "%@에 저장됨"
        ),
        .home_save_mix_failed: tr(
            en: "Couldn't save mix", es: "No se pudo guardar el mix", fr: "Impossible d'enregistrer le mix", de: "Mix konnte nicht gespeichert werden", pt: "Não foi possível guardar o mix", it: "Impossibile salvare il mix",
            nl: "Mix opslaan mislukt", ru: "Не удалось сохранить микс", pl: "Nie udało się zapisać miksu", tr: "Mix kaydedilemedi", sv: "Kunde inte spara mixen", nb: "Kunne ikke lagre miksen",
            da: "Kunne ikke gemme mixet", fi: "Miksin tallennus epäonnistui", zh: "无法保存混音", ja: "ミックスを保存できませんでした", ko: "믹스를 저장할 수 없음"
        ),
        .home_genre_mix_title: tr(
            en: "%@ Mix", es: "Mix de %@", fr: "Mix %@", de: "%@-Mix", pt: "Mix de %@", it: "Mix %@",
            nl: "%@-mix", ru: "Микс: %@", pl: "Miks %@", tr: "%@ Mix", sv: "%@-mix", nb: "%@-miks",
            da: "%@-mix", fi: "%@-miksaus", zh: "%@ 混音", ja: "%@ ミックス", ko: "%@ 믹스"
        ),
        .home_genre_mix_subtitle: tr(
            en: "Daily %@ mix", es: "Mix diario de %@", fr: "Mix %@ du jour", de: "Täglicher %@-Mix", pt: "Mix diário de %@", it: "Mix %@ giornaliero",
            nl: "Dagelijkse %@-mix", ru: "Ежедневный микс %@", pl: "Codzienny miks %@", tr: "Günlük %@ mix", sv: "Daglig %@-mix", nb: "Daglig %@-miks",
            da: "Dagligt %@-mix", fi: "Päivän %@-miksaus", zh: "每日 %@ 混音", ja: "今日の %@ ミックス", ko: "오늘의 %@ 믹스"
        ),
        .home_artist_mix_title: tr(
            en: "%@ Mix", es: "Mix de %@", fr: "Mix %@", de: "%@-Mix", pt: "Mix de %@", it: "Mix %@",
            nl: "%@-mix", ru: "Микс: %@", pl: "Miks %@", tr: "%@ Mix", sv: "%@-mix", nb: "%@-miks",
            da: "%@-mix", fi: "%@-miksaus", zh: "%@ 混音", ja: "%@ ミックス", ko: "%@ 믹스"
        ),
        .home_artist_mix_subtitle: tr(
            en: "Based on %@", es: "Basado en %@", fr: "Inspiré de %@", de: "Basierend auf %@", pt: "Baseado em %@", it: "Basato su %@",
            nl: "Gebaseerd op %@", ru: "На основе %@", pl: "Na podstawie %@", tr: "%@ temel alınarak", sv: "Baserat på %@", nb: "Basert på %@",
            da: "Baseret på %@", fi: "Perustuu artistiin %@", zh: "基于 %@", ja: "%@ をもとに作成", ko: "%@ 기반"
        ),
        .home_discovery_station: tr(
            en: "Discovery Station", es: "Estación de descubrimiento", fr: "Station découverte", de: "Entdeckungsstation", pt: "Estação de descoberta", it: "Stazione scoperta",
            nl: "Ontdekstation", ru: "Станция открытий", pl: "Stacja odkryć", tr: "Keşif İstasyonu", sv: "Upptäcktsstation", nb: "Oppdagelsesstasjon",
            da: "Opdagelsesstation", fi: "Löytöasema", zh: "发现电台", ja: "ディスカバリーステーション", ko: "발견 스테이션"
        ),
        .home_discovery_station_subtitle: tr(
            en: "Fresh picks for today", es: "Novedades para hoy", fr: "Sélection fraîche du jour", de: "Frische Tipps für heute", pt: "Escolhas frescas para hoje", it: "Scelte fresche per oggi",
            nl: "Verse tips voor vandaag", ru: "Свежая подборка на сегодня", pl: "Świeże propozycje na dziś", tr: "Bugünün yeni seçimleri", sv: "Färska tips för idag", nb: "Friske tips for i dag",
            da: "Friske valg til i dag", fi: "Tuoreita poimintoja tälle päivälle", zh: "今天的新鲜推荐", ja: "今日の新しいおすすめ", ko: "오늘의 새로운 추천"
        ),
        .home_heavy_rotation: tr(
            en: "Heavy Rotation", es: "En rotación", fr: "En boucle", de: "Heavy Rotation", pt: "Rotação frequente", it: "In rotazione",
            nl: "Veel gedraaid", ru: "Часто слушаете", pl: "Często odtwarzane", tr: "Sık Çalınanlar", sv: "Ofta spelat", nb: "Ofte spilt",
            da: "Ofte afspillet", fi: "Ahkerassa soitossa", zh: "常听循环", ja: "よく聴く曲", ko: "자주 듣는 곡"
        ),
        .home_heavy_rotation_subtitle: tr(
            en: "Songs you keep coming back to", es: "Canciones a las que siempre vuelves", fr: "Les titres que vous réécoutez", de: "Songs, zu denen du zurückkehrst", pt: "Músicas a que volta sempre", it: "Brani a cui torni spesso",
            nl: "Nummers waar je op terugkomt", ru: "Песни, к которым вы возвращаетесь", pl: "Utwory, do których wracasz", tr: "Tekrar tekrar dinlediğin şarkılar", sv: "Låtar du återvänder till", nb: "Låter du stadig vender tilbake til",
            da: "Sange du vender tilbage til", fi: "Kappaleet, joihin palaat", zh: "你反复回听的歌曲", ja: "何度も戻ってくる曲", ko: "계속 다시 듣는 곡"
        ),

        // Media metadata / sheets
        .media_title: tr(en: "Title", es: "Título", fr: "Titre", de: "Titel", pt: "Título", it: "Titolo", nl: "Titel", ru: "Название", pl: "Tytuł", tr: "Başlık", sv: "Titel", nb: "Tittel", da: "Titel", fi: "Nimi", zh: "标题", ja: "タイトル", ko: "제목"),
        .media_artist: tr(en: "Artist", es: "Artista", fr: "Artiste", de: "Künstler", pt: "Artista", it: "Artista", nl: "Artiest", ru: "Исполнитель", pl: "Wykonawca", tr: "Sanatçı", sv: "Artist", nb: "Artist", da: "Kunstner", fi: "Artisti", zh: "艺人", ja: "アーティスト", ko: "아티스트"),
        .media_album: tr(en: "Album", es: "Álbum", fr: "Album", de: "Album", pt: "Álbum", it: "Album", nl: "Album", ru: "Альбом", pl: "Album", tr: "Albüm", sv: "Album", nb: "Album", da: "Album", fi: "Albumi", zh: "专辑", ja: "アルバム", ko: "앨범"),
        .media_songs: tr(en: "Songs", es: "Canciones", fr: "Titres", de: "Songs", pt: "Músicas", it: "Brani", nl: "Nummers", ru: "Песни", pl: "Utwory", tr: "Şarkılar", sv: "Låtar", nb: "Låter", da: "Sange", fi: "Kappaleet", zh: "歌曲", ja: "曲", ko: "곡"),
        .media_duration: tr(en: "Duration", es: "Duración", fr: "Durée", de: "Dauer", pt: "Duração", it: "Durata", nl: "Duur", ru: "Длительность", pl: "Czas trwania", tr: "Süre", sv: "Längd", nb: "Varighet", da: "Varighed", fi: "Kesto", zh: "时长", ja: "長さ", ko: "길이"),
        .media_plays: tr(en: "Plays", es: "Reproducciones", fr: "Lectures", de: "Wiedergaben", pt: "Reproduções", it: "Riproduzioni", nl: "Afspelingen", ru: "Прослушивания", pl: "Odtworzenia", tr: "Çalma", sv: "Spelningar", nb: "Avspillinger", da: "Afspilninger", fi: "Toistot", zh: "播放次数", ja: "再生回数", ko: "재생"),
        .media_year: tr(en: "Year", es: "Año", fr: "Année", de: "Jahr", pt: "Ano", it: "Anno", nl: "Jaar", ru: "Год", pl: "Rok", tr: "Yıl", sv: "År", nb: "År", da: "År", fi: "Vuosi", zh: "年份", ja: "年", ko: "연도"),
        .media_genre: tr(en: "Genre", es: "Género", fr: "Genre", de: "Genre", pt: "Género", it: "Genere", nl: "Genre", ru: "Жанр", pl: "Gatunek", tr: "Tür", sv: "Genre", nb: "Sjanger", da: "Genre", fi: "Genre", zh: "流派", ja: "ジャンル", ko: "장르"),
        .media_added: tr(en: "Added", es: "Añadido", fr: "Ajouté", de: "Hinzugefügt", pt: "Adicionado", it: "Aggiunto", nl: "Toegevoegd", ru: "Добавлено", pl: "Dodano", tr: "Eklendi", sv: "Tillagt", nb: "Lagt til", da: "Tilføjet", fi: "Lisätty", zh: "已添加", ja: "追加日", ko: "추가됨"),
        .media_label: tr(en: "Label", es: "Sello", fr: "Label", de: "Label", pt: "Editora", it: "Etichetta", nl: "Label", ru: "Лейбл", pl: "Wytwórnia", tr: "Plak şirketi", sv: "Skivbolag", nb: "Plateselskap", da: "Pladeselskab", fi: "Levy-yhtiö", zh: "厂牌", ja: "レーベル", ko: "레이블"),
        .media_bit_rate: tr(en: "Bit Rate", es: "Tasa de bits", fr: "Débit", de: "Bitrate", pt: "Taxa de bits", it: "Bitrate", nl: "Bitsnelheid", ru: "Битрейт", pl: "Szybkość bitowa", tr: "Bit hızı", sv: "Bithastighet", nb: "Bithastighet", da: "Bithastighed", fi: "Bittinopeus", zh: "比特率", ja: "ビットレート", ko: "비트 전송률"),
        .media_sample_rate: tr(en: "Sample Rate", es: "Frecuencia de muestreo", fr: "Fréquence d'échantillonnage", de: "Samplerate", pt: "Taxa de amostragem", it: "Frequenza di campionamento", nl: "Samplefrequentie", ru: "Частота дискретизации", pl: "Częstotliwość próbkowania", tr: "Örnekleme hızı", sv: "Samplingsfrekvens", nb: "Samplingsrate", da: "Samplingsfrekvens", fi: "Näytteenottotaajuus", zh: "采样率", ja: "サンプルレート", ko: "샘플 레이트"),
        .media_bit_depth: tr(en: "Bit Depth", es: "Profundidad de bits", fr: "Profondeur de bits", de: "Bittiefe", pt: "Profundidade de bits", it: "Profondità bit", nl: "Bitdiepte", ru: "Битовая глубина", pl: "Głębia bitowa", tr: "Bit derinliği", sv: "Bitdjup", nb: "Bitdybde", da: "Bitdybde", fi: "Bittisyvyys", zh: "位深", ja: "ビット深度", ko: "비트 깊이"),
        .media_format: tr(en: "Format", es: "Formato", fr: "Format", de: "Format", pt: "Formato", it: "Formato", nl: "Formaat", ru: "Формат", pl: "Format", tr: "Biçim", sv: "Format", nb: "Format", da: "Format", fi: "Muoto", zh: "格式", ja: "形式", ko: "형식"),
        .media_file_type: tr(en: "File Type", es: "Tipo de archivo", fr: "Type de fichier", de: "Dateityp", pt: "Tipo de ficheiro", it: "Tipo file", nl: "Bestandstype", ru: "Тип файла", pl: "Typ pliku", tr: "Dosya türü", sv: "Filtyp", nb: "Filtype", da: "Filtype", fi: "Tiedostotyyppi", zh: "文件类型", ja: "ファイル形式", ko: "파일 유형"),
        .media_file_size: tr(en: "File Size", es: "Tamaño de archivo", fr: "Taille du fichier", de: "Dateigröße", pt: "Tamanho do ficheiro", it: "Dimensione file", nl: "Bestandsgrootte", ru: "Размер файла", pl: "Rozmiar pliku", tr: "Dosya boyutu", sv: "Filstorlek", nb: "Filstørrelse", da: "Filstørrelse", fi: "Tiedoston koko", zh: "文件大小", ja: "ファイルサイズ", ko: "파일 크기"),
        .media_play_count: tr(en: "Play Count", es: "Reproducciones", fr: "Nombre de lectures", de: "Wiedergaben", pt: "Contagem de reproduções", it: "Numero riproduzioni", nl: "Aantal keren afgespeeld", ru: "Счётчик прослушиваний", pl: "Liczba odtworzeń", tr: "Çalma sayısı", sv: "Antal spelningar", nb: "Antall avspillinger", da: "Antal afspilninger", fi: "Toistokerrat", zh: "播放次数", ja: "再生回数", ko: "재생 횟수"),
        .media_path: tr(en: "Path", es: "Ruta", fr: "Chemin", de: "Pfad", pt: "Caminho", it: "Percorso", nl: "Pad", ru: "Путь", pl: "Ścieżka", tr: "Yol", sv: "Sökväg", nb: "Sti", da: "Sti", fi: "Polku", zh: "路径", ja: "パス", ko: "경로"),
        .song_info_title: tr(en: "Song Info", es: "Información de la canción", fr: "Infos du titre", de: "Song-Info", pt: "Info da música", it: "Info brano", nl: "Nummerinfo", ru: "Сведения о песне", pl: "Informacje o utworze", tr: "Şarkı bilgisi", sv: "Låtinfo", nb: "Låtinfo", da: "Sanginfo", fi: "Kappaleen tiedot", zh: "歌曲信息", ja: "曲の情報", ko: "곡 정보"),
        .album_stats_title: tr(en: "Album Stats", es: "Estadísticas del álbum", fr: "Stats de l'album", de: "Albumstatistik", pt: "Estatísticas do álbum", it: "Statistiche album", nl: "Albumstatistieken", ru: "Статистика альбома", pl: "Statystyki albumu", tr: "Albüm istatistikleri", sv: "Albumstatistik", nb: "Albumstatistikk", da: "Albumstatistik", fi: "Albumin tilastot", zh: "专辑统计", ja: "アルバム統計", ko: "앨범 통계"),
        .settings_title: [
            .english: "Settings", .spanish: "Ajustes", .french: "Réglages", .german: "Einstellungen",
            .portuguese: "Definições", .italian: "Impostazioni", .dutch: "Instellingen", .russian: "Настройки",
            .polish: "Ustawienia", .turkish: "Ayarlar", .swedish: "Inställningar", .norwegian: "Innstillinger",
            .danish: "Indstillinger", .finnish: "Asetukset", .chinese: "设置", .japanese: "設定", .korean: "설정",
        ],
        .settings_language: [
            .english: "Language", .spanish: "Idioma", .french: "Langue", .german: "Sprache",
            .portuguese: "Idioma", .italian: "Lingua", .dutch: "Taal", .russian: "Язык",
            .polish: "Język", .turkish: "Dil", .swedish: "Språk", .norwegian: "Språk",
            .danish: "Sprog", .finnish: "Kieli", .chinese: "语言", .japanese: "言語", .korean: "언어",
        ],
        .settings_search: [
            .english: "Search settings", .spanish: "Buscar ajustes", .french: "Rechercher dans les réglages",
            .german: "Einstellungen durchsuchen", .portuguese: "Pesquisar definições", .italian: "Cerca nelle impostazioni",
            .dutch: "Instellingen zoeken", .russian: "Поиск в настройках", .polish: "Szukaj w ustawieniach",
            .turkish: "Ayarlarda ara", .swedish: "Sök i inställningar", .norwegian: "Søk i innstillinger",
            .danish: "Søg i indstillinger", .finnish: "Hae asetuksista", .chinese: "搜索设置",
            .japanese: "設定を検索", .korean: "설정 검색",
        ],
        .language_picker_footer: [
            .english: "Changes apply across the app right away. English is the default.",
            .spanish: "Los cambios se aplican en toda la app al instante. El inglés es el idioma predeterminado.",
            .french: "Les changements s'appliquent immédiatement dans toute l'app. L'anglais est la langue par défaut.",
            .german: "Änderungen gelten sofort in der gesamten App. Englisch ist die Standardsprache.",
            .portuguese: "As alterações aplicam-se de imediato em toda a app. O inglês é o idioma predefinido.",
            .italian: "Le modifiche si applicano subito in tutta l'app. L'inglese è la lingua predefinita.",
            .dutch: "Wijzigingen worden direct in de hele app toegepast. Engels is de standaard.",
            .russian: "Изменения сразу применяются во всём приложении. Английский — язык по умолчанию.",
            .polish: "Zmiany są od razu stosowane w całej aplikacji. Domyślnym językiem jest angielski.",
            .turkish: "Değişiklikler uygulamanın tamamında hemen geçerli olur. Varsayılan dil İngilizce'dir.",
            .swedish: "Ändringar tillämpas direkt i hela appen. Engelska är standard.",
            .norwegian: "Endringer brukes umiddelbart i hele appen. Engelsk er standard.",
            .danish: "Ændringer træder i kraft i hele appen med det samme. Engelsk er standard.",
            .finnish: "Muutokset tulevat heti voimaan koko sovelluksessa. Englanti on oletuskieli.",
            .chinese: "更改会立即应用到整个应用。默认语言为英语。",
            .japanese: "変更はアプリ全体にすぐ反映されます。デフォルトは英語です。",
            .korean: "변경 사항은 앱 전체에 즉시 적용됩니다. 기본 언어는 영어입니다.",
        ],
        .settings_section_playback: [
            .english: "Playback", .spanish: "Reproducción", .french: "Lecture", .german: "Wiedergabe",
            .portuguese: "Reprodução", .italian: "Riproduzione", .dutch: "Afspelen", .russian: "Воспроизведение",
            .polish: "Odtwarzanie", .turkish: "Oynatma", .swedish: "Uppspelning", .norwegian: "Avspilling",
            .danish: "Afspilning", .finnish: "Toisto", .chinese: "播放", .japanese: "再生", .korean: "재생",
        ],
        .settings_section_audio: [
            .english: "Audio", .spanish: "Audio", .french: "Audio", .german: "Audio",
            .portuguese: "Áudio", .italian: "Audio", .dutch: "Audio", .russian: "Звук",
            .polish: "Dźwięk", .turkish: "Ses", .swedish: "Ljud", .norwegian: "Lyd",
            .danish: "Lyd", .finnish: "Ääni", .chinese: "音频", .japanese: "オーディオ", .korean: "오디오",
        ],
        .settings_section_streaming: [
            .english: "Streaming & Downloads", .spanish: "Streaming y descargas", .french: "Streaming et téléchargements",
            .german: "Streaming & Downloads", .portuguese: "Streaming e transferências", .italian: "Streaming e download",
            .dutch: "Streamen en downloads", .russian: "Потоки и загрузки", .polish: "Strumieniowanie i pobieranie",
            .turkish: "Yayın ve indirmeler", .swedish: "Strömning och nedladdningar", .norwegian: "Strømming og nedlastinger",
            .danish: "Streaming og downloads", .finnish: "Suoratoisto ja lataukset", .chinese: "流媒体与下载",
            .japanese: "ストリーミングとダウンロード", .korean: "스트리밍 및 다운로드",
        ],
        .settings_section_performance: [
            .english: "Performance", .spanish: "Rendimiento", .french: "Performances", .german: "Leistung",
            .portuguese: "Desempenho", .italian: "Prestazioni", .dutch: "Prestaties", .russian: "Производительность",
            .polish: "Wydajność", .turkish: "Performans", .swedish: "Prestanda", .norwegian: "Ytelse",
            .danish: "Ydeevne", .finnish: "Suorituskyky", .chinese: "性能", .japanese: "パフォーマンス", .korean: "성능",
        ],
        .settings_section_appearance: [
            .english: "Appearance", .spanish: "Apariencia", .french: "Apparence", .german: "Darstellung",
            .portuguese: "Aparência", .italian: "Aspetto", .dutch: "Weergave", .russian: "Оформление",
            .polish: "Wygląd", .turkish: "Görünüm", .swedish: "Utseende", .norwegian: "Utseende",
            .danish: "Udseende", .finnish: "Ulkoasu", .chinese: "外观", .japanese: "外観", .korean: "화면 표시",
        ],
        .settings_section_notifications: [
            .english: "Notifications", .spanish: "Notificaciones", .french: "Notifications", .german: "Mitteilungen",
            .portuguese: "Notificações", .italian: "Notifiche", .dutch: "Meldingen", .russian: "Уведомления",
            .polish: "Powiadomienia", .turkish: "Bildirimler", .swedish: "Aviseringar", .norwegian: "Varsler",
            .danish: "Notifikationer", .finnish: "Ilmoitukset", .chinese: "通知", .japanese: "通知", .korean: "알림",
        ],
        .settings_section_backups: [
            .english: "Backups", .spanish: "Copias de seguridad", .french: "Sauvegardes", .german: "Backups",
            .portuguese: "Cópias de segurança", .italian: "Backup", .dutch: "Back-ups", .russian: "Резервные копии",
            .polish: "Kopie zapasowe", .turkish: "Yedeklemeler", .swedish: "Säkerhetskopior", .norwegian: "Sikkerhetskopier",
            .danish: "Sikkerhedskopier", .finnish: "Varmuuskopiot", .chinese: "备份", .japanese: "バックアップ", .korean: "백업",
        ],
        .settings_section_server: [
            .english: "Server", .spanish: "Servidor", .french: "Serveur", .german: "Server",
            .portuguese: "Servidor", .italian: "Server", .dutch: "Server", .russian: "Сервер",
            .polish: "Serwer", .turkish: "Sunucu", .swedish: "Server", .norwegian: "Server",
            .danish: "Server", .finnish: "Palvelin", .chinese: "服务器", .japanese: "サーバー", .korean: "서버",
        ],
        .settings_section_storage: [
            .english: "Storage", .spanish: "Almacenamiento", .french: "Stockage", .german: "Speicher",
            .portuguese: "Armazenamento", .italian: "Spazio", .dutch: "Opslag", .russian: "Хранилище",
            .polish: "Pamięć", .turkish: "Depolama", .swedish: "Lagring", .norwegian: "Lagring",
            .danish: "Lagring", .finnish: "Tallennustila", .chinese: "存储", .japanese: "ストレージ", .korean: "저장 공간",
        ],
        .settings_section_about: [
            .english: "About", .spanish: "Acerca de", .french: "À propos", .german: "Über",
            .portuguese: "Acerca de", .italian: "Informazioni", .dutch: "Over", .russian: "О приложении",
            .polish: "O aplikacji", .turkish: "Hakkında", .swedish: "Om", .norwegian: "Om",
            .danish: "Om", .finnish: "Tietoja", .chinese: "关于", .japanese: "情報", .korean: "정보",
        ],
        .settings_section_developer: [
            .english: "Developer", .spanish: "Desarrollador", .french: "Développeur", .german: "Entwickler",
            .portuguese: "Programador", .italian: "Sviluppatore", .dutch: "Ontwikkelaar", .russian: "Разработчик",
            .polish: "Deweloper", .turkish: "Geliştirici", .swedish: "Utvecklare", .norwegian: "Utvikler",
            .danish: "Udvikler", .finnish: "Kehittäjä", .chinese: "开发者", .japanese: "開発者", .korean: "개발자",
        ],
        .appearance_theme: [
            .english: "Theme", .spanish: "Tema", .french: "Thème", .german: "Design",
            .portuguese: "Tema", .italian: "Tema", .dutch: "Thema", .russian: "Тема",
            .polish: "Motyw", .turkish: "Tema", .swedish: "Tema", .norwegian: "Tema",
            .danish: "Tema", .finnish: "Teema", .chinese: "主题", .japanese: "テーマ", .korean: "테마",
        ],
        .appearance_lossless_badge: [
            .english: "Show Lossless Badge", .spanish: "Mostrar insignia sin pérdida", .french: "Afficher le badge sans perte",
            .german: "Lossless-Abzeichen anzeigen", .portuguese: "Mostrar selo sem perdas", .italian: "Mostra badge lossless",
            .dutch: "Lossless-badge tonen", .russian: "Показывать значок Lossless", .polish: "Pokaż plakietkę Lossless",
            .turkish: "Lossless rozetini göster", .swedish: "Visa lossless-märke", .norwegian: "Vis lossless-merke",
            .danish: "Vis lossless-mærke", .finnish: "Näytä lossless-merkki", .chinese: "显示无损标记",
            .japanese: "ロスレスバッジを表示", .korean: "무손실 배지 표시",
        ],
        .appearance_live_artwork: [
            .english: "Live Artwork", .spanish: "Carátula animada", .french: "Pochette animée", .german: "Live-Cover",
            .portuguese: "Capa animada", .italian: "Copertina animata", .dutch: "Live albumhoes", .russian: "Живая обложка",
            .polish: "Animowana okładka", .turkish: "Canlı kapak", .swedish: "Levande omslag", .norwegian: "Levende omslag",
            .danish: "Levende omslag", .finnish: "Elävä kansikuva", .chinese: "动态封面", .japanese: "ライブアートワーク", .korean: "라이브 아트워크",
        ],
        .appearance_stylized_cover: [
            .english: "Stylized Player Cover", .spanish: "Carátula estilizada", .french: "Pochette stylisée du lecteur",
            .german: "Stilisiertes Player-Cover", .portuguese: "Capa estilizada do leitor", .italian: "Copertina stilizzata del player",
            .dutch: "Gestileerde spelerhoes", .russian: "Стилизованная обложка плеера", .polish: "Stylizowana okładka odtwarzacza",
            .turkish: "Stilize oynatıcı kapağı", .swedish: "Stiliserat spelaromslag", .norwegian: "Stilisert spilleromslag",
            .danish: "Stiliseret afspilleromslag", .finnish: "Tyylitelty soittimen kansi", .chinese: "风格化播放器封面",
            .japanese: "スタイル付きプレーヤーカバー", .korean: "스타일 플레이어 커버",
        ],
        .appearance_song_artwork_lists: [
            .english: "Song Artwork in Lists", .spanish: "Carátulas en las listas", .french: "Pochettes dans les listes",
            .german: "Song-Cover in Listen", .portuguese: "Capas nas listas", .italian: "Copertine negli elenchi",
            .dutch: "Albumhoes in lijsten", .russian: "Обложки в списках", .polish: "Okładki na listach",
            .turkish: "Listelerde şarkı kapağı", .swedish: "Omslag i listor", .norwegian: "Omslag i lister",
            .danish: "Omslag i lister", .finnish: "Kansikuvat luetteloissa", .chinese: "列表中显示歌曲封面",
            .japanese: "リストに曲のアートワークを表示", .korean: "목록에 곡 아트워크 표시",
        ],
        .appearance_dynamic_background: [
            .english: "Dynamic Player Background", .spanish: "Fondo dinámico del reproductor", .french: "Arrière-plan dynamique du lecteur",
            .german: "Dynamischer Player-Hintergrund", .portuguese: "Fundo dinâmico do leitor", .italian: "Sfondo dinamico del player",
            .dutch: "Dynamische spelerachtergrond", .russian: "Динамический фон плеера", .polish: "Dynamiczne tło odtwarzacza",
            .turkish: "Dinamik oynatıcı arka planı", .swedish: "Dynamisk spelarbakgrund", .norwegian: "Dynamisk spillerbakgrunn",
            .danish: "Dynamisk afspillerbaggrund", .finnish: "Dynaaminen soittimen tausta", .chinese: "动态播放器背景",
            .japanese: "ダイナミックなプレーヤー背景", .korean: "동적 플레이어 배경",
        ],
        .appearance_accent_color: [
            .english: "Accent Color", .spanish: "Color de acento", .french: "Couleur d'accent", .german: "Akzentfarbe",
            .portuguese: "Cor de destaque", .italian: "Colore d'accento", .dutch: "Accentkleur", .russian: "Акцентный цвет",
            .polish: "Kolor akcentu", .turkish: "Vurgu rengi", .swedish: "Accentfärg", .norwegian: "Aksentfarge",
            .danish: "Accentfarve", .finnish: "Korostusväri", .chinese: "强调色", .japanese: "アクセントカラー", .korean: "강조 색상",
        ],
        .appearance_hidden_albums: [
            .english: "Hidden Albums", .spanish: "Álbumes ocultos", .french: "Albums masqués", .german: "Ausgeblendete Alben",
            .portuguese: "Álbuns ocultos", .italian: "Album nascosti", .dutch: "Verborgen albums", .russian: "Скрытые альбомы",
            .polish: "Ukryte albumy", .turkish: "Gizli albümler", .swedish: "Dolda album", .norwegian: "Skjulte album",
            .danish: "Skjulte album", .finnish: "Piilotetut albumit", .chinese: "隐藏的专辑", .japanese: "非表示のアルバム", .korean: "숨긴 앨범",
        ],
        .hidden_albums_none: [
            .english: "None", .spanish: "Ninguno", .french: "Aucun", .german: "Keine",
            .portuguese: "Nenhum", .italian: "Nessuno", .dutch: "Geen", .russian: "Нет",
            .polish: "Brak", .turkish: "Yok", .swedish: "Inga", .norwegian: "Ingen",
            .danish: "Ingen", .finnish: "Ei yhtään", .chinese: "无", .japanese: "なし", .korean: "없음",
        ],
        .hidden_albums_count: [
            .english: "%d hidden", .spanish: "%d ocultos", .french: "%d masqués", .german: "%d ausgeblendet",
            .portuguese: "%d ocultos", .italian: "%d nascosti", .dutch: "%d verborgen", .russian: "%d скрыто",
            .polish: "%d ukrytych", .turkish: "%d gizli", .swedish: "%d dolda", .norwegian: "%d skjult",
            .danish: "%d skjulte", .finnish: "%d piilotettu", .chinese: "已隐藏 %d 个", .japanese: "%d 件非表示", .korean: "%d개 숨김",
        ],
        .hidden_albums_sort: [
            .english: "Sort", .spanish: "Ordenar", .french: "Trier", .german: "Sortieren",
            .portuguese: "Ordenar", .italian: "Ordina", .dutch: "Sorteren", .russian: "Сортировка",
            .polish: "Sortuj", .turkish: "Sırala", .swedish: "Sortera", .norwegian: "Sorter",
            .danish: "Sorter", .finnish: "Lajittele", .chinese: "排序", .japanese: "並べ替え", .korean: "정렬",
        ],
        .hidden_albums_sort_visible_first: [
            .english: "Visible First", .spanish: "Visibles primero", .french: "Visibles d'abord", .german: "Sichtbare zuerst",
            .portuguese: "Visíveis primeiro", .italian: "Visibili prima", .dutch: "Zichtbaar eerst", .russian: "Сначала видимые",
            .polish: "Widoczne najpierw", .turkish: "Önce görünenler", .swedish: "Synliga först", .norwegian: "Synlige først",
            .danish: "Synlige først", .finnish: "Näkyvät ensin", .chinese: "先显示可见", .japanese: "表示中を先に", .korean: "표시 항목 먼저",
        ],
        .hidden_albums_sort_hidden_first: [
            .english: "Hidden First", .spanish: "Ocultos primero", .french: "Masqués d'abord", .german: "Ausgeblendete zuerst",
            .portuguese: "Ocultos primeiro", .italian: "Nascosti prima", .dutch: "Verborgen eerst", .russian: "Сначала скрытые",
            .polish: "Ukryte najpierw", .turkish: "Önce gizliler", .swedish: "Dolda först", .norwegian: "Skjulte først",
            .danish: "Skjulte først", .finnish: "Piilotetut ensin", .chinese: "先显示隐藏", .japanese: "非表示を先に", .korean: "숨김 항목 먼저",
        ],
        .hidden_albums_search: [
            .english: "Search albums", .spanish: "Buscar álbumes", .french: "Rechercher des albums", .german: "Alben suchen",
            .portuguese: "Pesquisar álbuns", .italian: "Cerca album", .dutch: "Albums zoeken", .russian: "Поиск альбомов",
            .polish: "Szukaj albumów", .turkish: "Albüm ara", .swedish: "Sök album", .norwegian: "Søk i album",
            .danish: "Søg i album", .finnish: "Hae albumeja", .chinese: "搜索专辑", .japanese: "アルバムを検索", .korean: "앨범 검색",
        ],
        .hidden_albums_hide_visible: [
            .english: "Hide Visible", .spanish: "Ocultar visibles", .french: "Masquer visibles", .german: "Sichtbare ausblenden",
            .portuguese: "Ocultar visíveis", .italian: "Nascondi visibili", .dutch: "Zichtbare verbergen", .russian: "Скрыть видимые",
            .polish: "Ukryj widoczne", .turkish: "Görünenleri gizle", .swedish: "Dölj synliga", .norwegian: "Skjul synlige",
            .danish: "Skjul synlige", .finnish: "Piilota näkyvät", .chinese: "隐藏可见项", .japanese: "表示中を非表示", .korean: "표시 항목 숨기기",
        ],
        .hidden_albums_show_visible: [
            .english: "Show Visible", .spanish: "Mostrar visibles", .french: "Afficher visibles", .german: "Sichtbare anzeigen",
            .portuguese: "Mostrar visíveis", .italian: "Mostra visibili", .dutch: "Zichtbare tonen", .russian: "Показать видимые",
            .polish: "Pokaż widoczne", .turkish: "Görünenleri göster", .swedish: "Visa synliga", .norwegian: "Vis synlige",
            .danish: "Vis synlige", .finnish: "Näytä näkyvät", .chinese: "显示可见项", .japanese: "表示中を表示", .korean: "표시 항목 보이기",
        ],
        .hidden_albums_show_all: [
            .english: "Show All", .spanish: "Mostrar todo", .french: "Tout afficher", .german: "Alle anzeigen",
            .portuguese: "Mostrar tudo", .italian: "Mostra tutto", .dutch: "Alles tonen", .russian: "Показать все",
            .polish: "Pokaż wszystko", .turkish: "Tümünü göster", .swedish: "Visa alla", .norwegian: "Vis alle",
            .danish: "Vis alle", .finnish: "Näytä kaikki", .chinese: "显示全部", .japanese: "すべて表示", .korean: "모두 보이기",
        ],
        .hidden_albums_empty: [
            .english: "No albums found", .spanish: "No se encontraron álbumes", .french: "Aucun album trouvé", .german: "Keine Alben gefunden",
            .portuguese: "Nenhum álbum encontrado", .italian: "Nessun album trovato", .dutch: "Geen albums gevonden", .russian: "Альбомы не найдены",
            .polish: "Nie znaleziono albumów", .turkish: "Albüm bulunamadı", .swedish: "Inga album hittades", .norwegian: "Ingen album funnet",
            .danish: "Ingen album fundet", .finnish: "Albumeja ei löytynyt", .chinese: "未找到专辑", .japanese: "アルバムが見つかりません", .korean: "앨범을 찾을 수 없음",
        ],
        .hidden_albums_no_matches: [
            .english: "No matches", .spanish: "Sin coincidencias", .french: "Aucun résultat", .german: "Keine Treffer",
            .portuguese: "Sem resultados", .italian: "Nessun risultato", .dutch: "Geen resultaten", .russian: "Нет совпадений",
            .polish: "Brak wyników", .turkish: "Eşleşme yok", .swedish: "Inga träffar", .norwegian: "Ingen treff",
            .danish: "Ingen resultater", .finnish: "Ei osumia", .chinese: "无匹配项", .japanese: "一致なし", .korean: "일치 항목 없음",
        ],
        .hidden_albums_no_server: [
            .english: "Connect to a server to manage hidden albums.", .spanish: "Conéctate a un servidor para gestionar álbumes ocultos.", .french: "Connectez-vous à un serveur pour gérer les albums masqués.",
            .german: "Verbinde dich mit einem Server, um ausgeblendete Alben zu verwalten.", .portuguese: "Ligue-se a um servidor para gerir álbuns ocultos.", .italian: "Connettiti a un server per gestire gli album nascosti.",
            .dutch: "Maak verbinding met een server om verborgen albums te beheren.", .russian: "Подключитесь к серверу, чтобы управлять скрытыми альбомами.", .polish: "Połącz się z serwerem, aby zarządzać ukrytymi albumami.",
            .turkish: "Gizli albümleri yönetmek için bir sunucuya bağlan.", .swedish: "Anslut till en server för att hantera dolda album.", .norwegian: "Koble til en server for å administrere skjulte album.",
            .danish: "Opret forbindelse til en server for at administrere skjulte album.", .finnish: "Yhdistä palvelimeen hallitaksesi piilotettuja albumeja.", .chinese: "连接服务器以管理隐藏的专辑。",
            .japanese: "非表示のアルバムを管理するにはサーバーに接続してください。", .korean: "숨긴 앨범을 관리하려면 서버에 연결하세요.",
        ],
        .artist_singles: [
            .english: "Singles", .spanish: "Sencillos", .french: "Singles", .german: "Singles",
            .portuguese: "Singles", .italian: "Singoli", .dutch: "Singles", .russian: "Синглы",
            .polish: "Single", .turkish: "Single'lar", .swedish: "Singlar", .norwegian: "Singler",
            .danish: "Singler", .finnish: "Singlet", .chinese: "单曲", .japanese: "シングル", .korean: "싱글",
        ],
        .theme_dark: [
            .english: "Dark", .spanish: "Oscuro", .french: "Sombre", .german: "Dunkel",
            .portuguese: "Escuro", .italian: "Scuro", .dutch: "Donker", .russian: "Тёмная",
            .polish: "Ciemny", .turkish: "Koyu", .swedish: "Mörkt", .norwegian: "Mørk",
            .danish: "Mørk", .finnish: "Tumma", .chinese: "深色", .japanese: "ダーク", .korean: "다크",
        ],
        .theme_amoled: [
            .english: "AMOLED", .spanish: "AMOLED", .french: "AMOLED", .german: "AMOLED",
            .portuguese: "AMOLED", .italian: "AMOLED", .dutch: "AMOLED", .russian: "AMOLED",
            .polish: "AMOLED", .turkish: "AMOLED", .swedish: "AMOLED", .norwegian: "AMOLED",
            .danish: "AMOLED", .finnish: "AMOLED", .chinese: "AMOLED", .japanese: "AMOLED", .korean: "AMOLED",
        ],
        .theme_light: [
            .english: "Light", .spanish: "Claro", .french: "Clair", .german: "Hell",
            .portuguese: "Claro", .italian: "Chiaro", .dutch: "Licht", .russian: "Светлая",
            .polish: "Jasny", .turkish: "Açık", .swedish: "Ljust", .norwegian: "Lys",
            .danish: "Lys", .finnish: "Vaalea", .chinese: "浅色", .japanese: "ライト", .korean: "라이트",
        ],

        // Notifications / toasts
        .notif_added_to_favorites: [
            .english: "Added to Favorites", .spanish: "Añadido a Favoritos", .french: "Ajouté aux favoris",
            .german: "Zu Favoriten hinzugefügt", .portuguese: "Adicionado aos Favoritos", .italian: "Aggiunto ai preferiti",
            .dutch: "Toegevoegd aan favorieten", .russian: "Добавлено в избранное", .polish: "Dodano do ulubionych",
            .turkish: "Favorilere eklendi", .swedish: "Tillagd i favoriter", .norwegian: "Lagt til i favoritter",
            .danish: "Tilføjet til favoritter", .finnish: "Lisätty suosikkeihin", .chinese: "已添加到收藏",
            .japanese: "お気に入りに追加しました", .korean: "즐겨찾기에 추가됨",
        ],
        .notif_removed_from_favorites: [
            .english: "Removed from Favorites", .spanish: "Eliminado de Favoritos", .french: "Retiré des favoris",
            .german: "Aus Favoriten entfernt", .portuguese: "Removido dos Favoritos", .italian: "Rimosso dai preferiti",
            .dutch: "Verwijderd uit favorieten", .russian: "Удалено из избранного", .polish: "Usunięto z ulubionych",
            .turkish: "Favorilerden kaldırıldı", .swedish: "Borttagen från favoriter", .norwegian: "Fjernet fra favoritter",
            .danish: "Fjernet fra favoritter", .finnish: "Poistettu suosikeista", .chinese: "已从收藏中移除",
            .japanese: "お気に入りから削除しました", .korean: "즐겨찾기에서 제거됨",
        ],
        .notif_added_to_queue: [
            .english: "Added to Queue", .spanish: "Añadido a la cola", .french: "Ajouté à la file",
            .german: "Zur Warteschlange hinzugefügt", .portuguese: "Adicionado à fila", .italian: "Aggiunto alla coda",
            .dutch: "Toegevoegd aan wachtrij", .russian: "Добавлено в очередь", .polish: "Dodano do kolejki",
            .turkish: "Sıraya eklendi", .swedish: "Tillagd i kön", .norwegian: "Lagt til i køen",
            .danish: "Tilføjet til køen", .finnish: "Lisätty jonoon", .chinese: "已加入队列",
            .japanese: "キューに追加しました", .korean: "대기열에 추가됨",
        ],
        .notif_playing_next: [
            .english: "Playing Next", .spanish: "Se reproducirá a continuación", .french: "Lecture suivante",
            .german: "Wird als Nächstes gespielt", .portuguese: "A seguir", .italian: "Riproduci dopo",
            .dutch: "Volgende afspelen", .russian: "Следующий трек", .polish: "Następne w kolejce",
            .turkish: "Sıradaki çalınıyor", .swedish: "Spelas härnäst", .norwegian: "Spilles neste",
            .danish: "Afspilles næst", .finnish: "Toistetaan seuraavaksi", .chinese: "下一首播放",
            .japanese: "次に再生", .korean: "다음에 재생",
        ],
        .notif_download_cancelled: [
            .english: "Download cancelled", .spanish: "Descarga cancelada", .french: "Téléchargement annulé",
            .german: "Download abgebrochen", .portuguese: "Transferência cancelada", .italian: "Download annullato",
            .dutch: "Download geannuleerd", .russian: "Загрузка отменена", .polish: "Anulowano pobieranie",
            .turkish: "İndirme iptal edildi", .swedish: "Nedladdning avbruten", .norwegian: "Nedlasting avbrutt",
            .danish: "Download annulleret", .finnish: "Lataus peruutettu", .chinese: "已取消下载",
            .japanese: "ダウンロードをキャンセルしました", .korean: "다운로드 취소됨",
        ],
        .notif_download_removed: [
            .english: "Download removed", .spanish: "Descarga eliminada", .french: "Téléchargement supprimé",
            .german: "Download entfernt", .portuguese: "Transferência removida", .italian: "Download rimosso",
            .dutch: "Download verwijderd", .russian: "Загрузка удалена", .polish: "Usunięto pobranie",
            .turkish: "İndirme kaldırıldı", .swedish: "Nedladdning borttagen", .norwegian: "Nedlasting fjernet",
            .danish: "Download fjernet", .finnish: "Lataus poistettu", .chinese: "已删除下载",
            .japanese: "ダウンロードを削除しました", .korean: "다운로드 제거됨",
        ],
        .notif_demo_no_downloads: [
            .english: "Downloads are disabled on the demo server",
            .spanish: "Las descargas están desactivadas en el servidor de demostración",
            .french: "Les téléchargements sont désactivés sur le serveur de démo",
            .german: "Downloads sind auf dem Demo-Server deaktiviert",
            .portuguese: "As transferências estão desativadas no servidor de demonstração",
            .italian: "I download sono disattivati sul server demo",
            .dutch: "Downloads zijn uitgeschakeld op de demoserver",
            .russian: "Загрузки отключены на демо-сервере",
            .polish: "Pobieranie jest wyłączone na serwerze demonstracyjnym",
            .turkish: "Demo sunucusunda indirmeler devre dışı",
            .swedish: "Nedladdningar är inaktiverade på demoservern",
            .norwegian: "Nedlastinger er deaktivert på demoserveren",
            .danish: "Downloads er deaktiveret på demoserveren",
            .finnish: "Lataukset on poistettu käytöstä demopalvelimella",
            .chinese: "演示服务器上已禁用下载",
            .japanese: "デモサーバーではダウンロードは無効です",
            .korean: "데모 서버에서는 다운로드가 비활성화됩니다",
        ],
        .notif_downloaded: [
            .english: "Downloaded %@", .spanish: "Descargado: %@", .french: "Téléchargé : %@",
            .german: "%@ geladen", .portuguese: "Transferido: %@", .italian: "Scaricato: %@",
            .dutch: "Gedownload: %@", .russian: "Загружено: %@", .polish: "Pobrano: %@",
            .turkish: "İndirildi: %@", .swedish: "Nedladdad: %@", .norwegian: "Lastet ned: %@",
            .danish: "Hentet: %@", .finnish: "Ladattu: %@", .chinese: "已下载 %@",
            .japanese: "%@ をダウンロードしました", .korean: "%@ 다운로드됨",
        ],
        .notif_downloads_cleared: [
            .english: "Downloads cleared", .spanish: "Descargas borradas", .french: "Téléchargements effacés",
            .german: "Downloads gelöscht", .portuguese: "Transferências limpas", .italian: "Download cancellati",
            .dutch: "Downloads gewist", .russian: "Загрузки очищены", .polish: "Wyczyszczono pobrania",
            .turkish: "İndirmeler temizlendi", .swedish: "Nedladdningar rensade", .norwegian: "Nedlastinger tømt",
            .danish: "Downloads ryddet", .finnish: "Lataukset tyhjennetty", .chinese: "已清除下载",
            .japanese: "ダウンロードを消去しました", .korean: "다운로드 지움",
        ],
        .notif_evicted_old_download: [
            .english: "Evicted old download", .spanish: "Descarga antigua eliminada", .french: "Ancien téléchargement supprimé",
            .german: "Alter Download entfernt", .portuguese: "Transferência antiga removida", .italian: "Vecchio download rimosso",
            .dutch: "Oude download verwijderd", .russian: "Старая загрузка удалена", .polish: "Usunięto stare pobranie",
            .turkish: "Eski indirme kaldırıldı", .swedish: "Gammal nedladdning borttagen", .norwegian: "Gammel nedlasting fjernet",
            .danish: "Gammel download fjernet", .finnish: "Vanha lataus poistettu", .chinese: "已清除旧下载",
            .japanese: "古いダウンロードを削除しました", .korean: "오래된 다운로드 제거됨",
        ],
        .notif_no_downloads_to_remove: [
            .english: "No downloads to remove", .spanish: "No hay descargas para eliminar", .french: "Aucun téléchargement à supprimer",
            .german: "Keine Downloads zum Entfernen", .portuguese: "Sem transferências para remover", .italian: "Nessun download da rimuovere",
            .dutch: "Geen downloads om te verwijderen", .russian: "Нет загрузок для удаления", .polish: "Brak pobrań do usunięcia",
            .turkish: "Kaldırılacak indirme yok", .swedish: "Inga nedladdningar att ta bort", .norwegian: "Ingen nedlastinger å fjerne",
            .danish: "Ingen downloads at fjerne", .finnish: "Ei poistettavia latauksia", .chinese: "没有可移除的下载",
            .japanese: "削除するダウンロードはありません", .korean: "제거할 다운로드가 없습니다",
        ],
        .notif_everything_downloaded: [
            .english: "Everything is already downloaded", .spanish: "Todo ya está descargado", .french: "Tout est déjà téléchargé",
            .german: "Alles ist bereits geladen", .portuguese: "Tudo já foi transferido", .italian: "Tutto è già scaricato",
            .dutch: "Alles is al gedownload", .russian: "Всё уже загружено", .polish: "Wszystko jest już pobrane",
            .turkish: "Her şey zaten indirildi", .swedish: "Allt är redan nedladdat", .norwegian: "Alt er allerede lastet ned",
            .danish: "Alt er allerede hentet", .finnish: "Kaikki on jo ladattu", .chinese: "全部已下载",
            .japanese: "すべてダウンロード済みです", .korean: "모두 이미 다운로드됨",
        ],
        .notif_downloading_n: [
            .english: "Downloading %d songs", .spanish: "Descargando %d canciones", .french: "Téléchargement de %d titres",
            .german: "%d Titel werden geladen", .portuguese: "A transferir %d músicas", .italian: "Download di %d brani",
            .dutch: "%d nummers downloaden", .russian: "Загрузка %d треков", .polish: "Pobieranie %d utworów",
            .turkish: "%d şarkı indiriliyor", .swedish: "Laddar ner %d låtar", .norwegian: "Laster ned %d sanger",
            .danish: "Henter %d sange", .finnish: "Ladataan %d kappaletta", .chinese: "正在下载 %d 首歌曲",
            .japanese: "%d 曲をダウンロード中", .korean: "%d곡 다운로드 중",
        ],
        .notif_couldnt_load: [
            .english: "Couldn't load %@", .spanish: "No se pudo cargar %@", .french: "Impossible de charger %@",
            .german: "%@ konnte nicht geladen werden", .portuguese: "Não foi possível carregar %@", .italian: "Impossibile caricare %@",
            .dutch: "Kan %@ niet laden", .russian: "Не удалось загрузить %@", .polish: "Nie można wczytać %@",
            .turkish: "%@ yüklenemedi", .swedish: "Det gick inte att läsa in %@", .norwegian: "Kunne ikke laste %@",
            .danish: "Kunne ikke indlæse %@", .finnish: "Kohteen %@ lataus epäonnistui", .chinese: "无法加载 %@",
            .japanese: "%@ を読み込めませんでした", .korean: "%@을(를) 불러올 수 없습니다",
        ],
        .notif_couldnt_load_album: [
            .english: "Couldn't load album", .spanish: "No se pudo cargar el álbum", .french: "Impossible de charger l'album",
            .german: "Album konnte nicht geladen werden", .portuguese: "Não foi possível carregar o álbum", .italian: "Impossibile caricare l'album",
            .dutch: "Kan album niet laden", .russian: "Не удалось загрузить альбом", .polish: "Nie można wczytać albumu",
            .turkish: "Albüm yüklenemedi", .swedish: "Det gick inte att läsa in albumet", .norwegian: "Kunne ikke laste albumet",
            .danish: "Kunne ikke indlæse albummet", .finnish: "Albumin lataus epäonnistui", .chinese: "无法加载专辑",
            .japanese: "アルバムを読み込めませんでした", .korean: "앨범을 불러올 수 없습니다",
        ],
        .notif_couldnt_load_artist: [
            .english: "Couldn't load artist", .spanish: "No se pudo cargar el artista", .french: "Impossible de charger l'artiste",
            .german: "Künstler konnte nicht geladen werden", .portuguese: "Não foi possível carregar o artista", .italian: "Impossibile caricare l'artista",
            .dutch: "Kan artiest niet laden", .russian: "Не удалось загрузить исполнителя", .polish: "Nie można wczytać wykonawcy",
            .turkish: "Sanatçı yüklenemedi", .swedish: "Det gick inte att läsa in artisten", .norwegian: "Kunne ikke laste artisten",
            .danish: "Kunne ikke indlæse kunstneren", .finnish: "Artistin lataus epäonnistui", .chinese: "无法加载艺人",
            .japanese: "アーティストを読み込めませんでした", .korean: "아티스트를 불러올 수 없습니다",
        ],
        .notif_could_not_connect: [
            .english: "Could not connect", .spanish: "No se pudo conectar", .french: "Connexion impossible",
            .german: "Verbindung fehlgeschlagen", .portuguese: "Não foi possível ligar", .italian: "Impossibile connettersi",
            .dutch: "Kan geen verbinding maken", .russian: "Не удалось подключиться", .polish: "Nie można połączyć",
            .turkish: "Bağlanılamadı", .swedish: "Det gick inte att ansluta", .norwegian: "Kunne ikke koble til",
            .danish: "Kunne ikke oprette forbindelse", .finnish: "Yhteyttä ei voitu muodostaa", .chinese: "无法连接",
            .japanese: "接続できませんでした", .korean: "연결할 수 없습니다",
        ],
        .notif_connection_saved: [
            .english: "Connection saved", .spanish: "Conexión guardada", .french: "Connexion enregistrée",
            .german: "Verbindung gespeichert", .portuguese: "Ligação guardada", .italian: "Connessione salvata",
            .dutch: "Verbinding opgeslagen", .russian: "Подключение сохранено", .polish: "Zapisano połączenie",
            .turkish: "Bağlantı kaydedildi", .swedish: "Anslutning sparad", .norwegian: "Tilkobling lagret",
            .danish: "Forbindelse gemt", .finnish: "Yhteys tallennettu", .chinese: "已保存连接",
            .japanese: "接続を保存しました", .korean: "연결 저장됨",
        ],
        .notif_connection_test_passed: [
            .english: "Connection test passed", .spanish: "Prueba de conexión correcta", .french: "Test de connexion réussi",
            .german: "Verbindungstest bestanden", .portuguese: "Teste de ligação aprovado", .italian: "Test di connessione riuscito",
            .dutch: "Verbindingstest geslaagd", .russian: "Проверка подключения пройдена", .polish: "Test połączenia udany",
            .turkish: "Bağlantı testi başarılı", .swedish: "Anslutningstest godkänt", .norwegian: "Tilkoblingstest bestått",
            .danish: "Forbindelsestest bestået", .finnish: "Yhteystesti onnistui", .chinese: "连接测试通过",
            .japanese: "接続テストに合格しました", .korean: "연결 테스트 통과",
        ],
        .notif_connection_test_failed: [
            .english: "Connection test failed", .spanish: "La prueba de conexión falló", .french: "Échec du test de connexion",
            .german: "Verbindungstest fehlgeschlagen", .portuguese: "O teste de ligação falhou", .italian: "Test di connessione fallito",
            .dutch: "Verbindingstest mislukt", .russian: "Проверка подключения не пройдена", .polish: "Test połączenia nieudany",
            .turkish: "Bağlantı testi başarısız", .swedish: "Anslutningstest misslyckades", .norwegian: "Tilkoblingstest mislyktes",
            .danish: "Forbindelsestest mislykkedes", .finnish: "Yhteystesti epäonnistui", .chinese: "连接测试失败",
            .japanese: "接続テストに失敗しました", .korean: "연결 테스트 실패",
        ],
        .notif_invalid_server_url: [
            .english: "Invalid server URL", .spanish: "URL del servidor no válida", .french: "URL du serveur invalide",
            .german: "Ungültige Server-URL", .portuguese: "URL do servidor inválido", .italian: "URL del server non valido",
            .dutch: "Ongeldige server-URL", .russian: "Неверный URL сервера", .polish: "Nieprawidłowy adres URL serwera",
            .turkish: "Geçersiz sunucu URL'si", .swedish: "Ogiltig server-URL", .norwegian: "Ugyldig server-URL",
            .danish: "Ugyldig server-URL", .finnish: "Virheellinen palvelimen URL", .chinese: "服务器网址无效",
            .japanese: "サーバー URL が無効です", .korean: "잘못된 서버 URL",
        ],
        .notif_invalid_cellular_url: [
            .english: "Invalid cellular URL", .spanish: "URL de datos móviles no válida", .french: "URL cellulaire invalide",
            .german: "Ungültige Mobilfunk-URL", .portuguese: "URL de dados móveis inválido", .italian: "URL dati cellulare non valido",
            .dutch: "Ongeldige mobiele URL", .russian: "Неверный URL для сотовой сети", .polish: "Nieprawidłowy adres URL sieci komórkowej",
            .turkish: "Geçersiz hücresel URL", .swedish: "Ogiltig mobil-URL", .norwegian: "Ugyldig mobil-URL",
            .danish: "Ugyldig mobil-URL", .finnish: "Virheellinen mobiilidatan URL", .chinese: "蜂窝网址无效",
            .japanese: "モバイルデータの URL が無効です", .korean: "잘못된 셀룰러 URL",
        ],
        .notif_home_refreshed: [
            .english: "Home refreshed", .spanish: "Inicio actualizado", .french: "Accueil actualisé",
            .german: "Startseite aktualisiert", .portuguese: "Início atualizado", .italian: "Home aggiornata",
            .dutch: "Start vernieuwd", .russian: "Главная обновлена", .polish: "Odświeżono stronę główną",
            .turkish: "Ana sayfa yenilendi", .swedish: "Hem uppdaterad", .norwegian: "Hjem oppdatert",
            .danish: "Hjem opdateret", .finnish: "Koti päivitetty", .chinese: "主页已刷新",
            .japanese: "ホームを更新しました", .korean: "홈 새로고침됨",
        ],
        .notif_artwork_cache_cleared: [
            .english: "Artwork cache cleared", .spanish: "Caché de carátulas borrada", .french: "Cache des pochettes vidé",
            .german: "Cover-Cache geleert", .portuguese: "Cache de capas limpa", .italian: "Cache delle copertine svuotata",
            .dutch: "Albumhoescache gewist", .russian: "Кэш обложек очищен", .polish: "Wyczyszczono pamięć podręczną okładek",
            .turkish: "Kapak önbelleği temizlendi", .swedish: "Omslagscache rensad", .norwegian: "Omslagsbuffer tømt",
            .danish: "Omslagscache ryddet", .finnish: "Kansikuvien välimuisti tyhjennetty", .chinese: "已清除封面缓存",
            .japanese: "アートワークのキャッシュを消去しました", .korean: "아트워크 캐시 지움",
        ],
        .notif_local_artwork_deleted: [
            .english: "Local artwork deleted", .spanish: "Carátulas locales eliminadas", .french: "Pochettes locales supprimées",
            .german: "Lokale Cover gelöscht", .portuguese: "Capas locais eliminadas", .italian: "Copertine locali eliminate",
            .dutch: "Lokale albumhoezen verwijderd", .russian: "Локальные обложки удалены", .polish: "Usunięto lokalne okładki",
            .turkish: "Yerel kapaklar silindi", .swedish: "Lokala omslag raderade", .norwegian: "Lokale omslag slettet",
            .danish: "Lokale omslag slettet", .finnish: "Paikalliset kansikuvat poistettu", .chinese: "已删除本地封面",
            .japanese: "ローカルのアートワークを削除しました", .korean: "로컬 아트워크 삭제됨",
        ],
        .notif_local_lyrics_cleared: [
            .english: "Local lyrics cleared", .spanish: "Letras locales borradas", .french: "Paroles locales effacées",
            .german: "Lokale Songtexte gelöscht", .portuguese: "Letras locais limpas", .italian: "Testi locali cancellati",
            .dutch: "Lokale songteksten gewist", .russian: "Локальные тексты очищены", .polish: "Wyczyszczono lokalne teksty",
            .turkish: "Yerel şarkı sözleri temizlendi", .swedish: "Lokala låttexter rensade", .norwegian: "Lokale sangtekster tømt",
            .danish: "Lokale sangtekster ryddet", .finnish: "Paikalliset sanoitukset tyhjennetty", .chinese: "已清除本地歌词",
            .japanese: "ローカルの歌詞を消去しました", .korean: "로컬 가사 지움",
        ],
        .notif_lyrics_up_to_date: [
            .english: "Lyrics already up to date", .spanish: "Las letras ya están actualizadas", .french: "Paroles déjà à jour",
            .german: "Songtexte sind bereits aktuell", .portuguese: "As letras já estão atualizadas", .italian: "I testi sono già aggiornati",
            .dutch: "Songteksten zijn al up-to-date", .russian: "Тексты уже актуальны", .polish: "Teksty są już aktualne",
            .turkish: "Şarkı sözleri zaten güncel", .swedish: "Låttexterna är redan uppdaterade", .norwegian: "Sangtekstene er allerede oppdatert",
            .danish: "Sangteksterne er allerede opdateret", .finnish: "Sanoitukset ovat jo ajan tasalla", .chinese: "歌词已是最新",
            .japanese: "歌詞はすでに最新です", .korean: "가사가 이미 최신입니다",
        ],
        .notif_lyrics_download_stopped: [
            .english: "Lyrics download stopped", .spanish: "Descarga de letras detenida", .french: "Téléchargement des paroles arrêté",
            .german: "Songtext-Download gestoppt", .portuguese: "Transferência de letras parada", .italian: "Download dei testi interrotto",
            .dutch: "Songtekst downloaden gestopt", .russian: "Загрузка текстов остановлена", .polish: "Zatrzymano pobieranie tekstów",
            .turkish: "Şarkı sözü indirme durduruldu", .swedish: "Nedladdning av låttexter stoppad", .norwegian: "Nedlasting av sangtekster stoppet",
            .danish: "Download af sangtekster stoppet", .finnish: "Sanoitusten lataus pysäytetty", .chinese: "已停止下载歌词",
            .japanese: "歌詞のダウンロードを停止しました", .korean: "가사 다운로드 중지됨",
        ],
        .notif_lyrics_download_complete: [
            .english: "Lyrics download complete", .spanish: "Descarga de letras completada", .french: "Téléchargement des paroles terminé",
            .german: "Songtext-Download abgeschlossen", .portuguese: "Transferência de letras concluída", .italian: "Download dei testi completato",
            .dutch: "Songtekst downloaden voltooid", .russian: "Загрузка текстов завершена", .polish: "Zakończono pobieranie tekstów",
            .turkish: "Şarkı sözü indirme tamamlandı", .swedish: "Nedladdning av låttexter klar", .norwegian: "Nedlasting av sangtekster fullført",
            .danish: "Download af sangtekster fuldført", .finnish: "Sanoitusten lataus valmis", .chinese: "歌词下载完成",
            .japanese: "歌詞のダウンロードが完了しました", .korean: "가사 다운로드 완료",
        ],
        .notif_logs_cleared: [
            .english: "Logs cleared", .spanish: "Registros borrados", .french: "Journaux effacés",
            .german: "Protokolle gelöscht", .portuguese: "Registos limpos", .italian: "Log cancellati",
            .dutch: "Logboeken gewist", .russian: "Журналы очищены", .polish: "Wyczyszczono dzienniki",
            .turkish: "Günlükler temizlendi", .swedish: "Loggar rensade", .norwegian: "Logger tømt",
            .danish: "Logfiler ryddet", .finnish: "Lokit tyhjennetty", .chinese: "已清除日志",
            .japanese: "ログを消去しました", .korean: "로그 지움",
        ],
        .notif_logs_zip_ready: [
            .english: "Logs zip ready", .spanish: "ZIP de registros listo", .french: "ZIP des journaux prêt",
            .german: "Protokoll-ZIP bereit", .portuguese: "ZIP de registos pronto", .italian: "ZIP dei log pronto",
            .dutch: "Logboek-zip klaar", .russian: "ZIP с журналами готов", .polish: "Plik ZIP dzienników gotowy",
            .turkish: "Günlük ZIP'i hazır", .swedish: "Logg-zip klar", .norwegian: "Logg-zip klar",
            .danish: "Log-zip klar", .finnish: "Lokien ZIP valmis", .chinese: "日志压缩包已就绪",
            .japanese: "ログの ZIP の準備ができました", .korean: "로그 ZIP 준비됨",
        ],
        .notif_logs_folder_fallback: [
            .english: "Logs export used folder fallback", .spanish: "Exportación de registros usó carpeta alternativa", .french: "Export des journaux : dossier de secours utilisé",
            .german: "Protokoll-Export nutzte Ordner-Fallback", .portuguese: "Exportação de registos usou pasta alternativa", .italian: "Esportazione log: usata cartella di riserva",
            .dutch: "Logboekexport gebruikte mapfallback", .russian: "Экспорт журналов использовал резервную папку", .polish: "Eksport dzienników użył folderu zapasowego",
            .turkish: "Günlük dışa aktarımı klasör yedeğini kullandı", .swedish: "Loggexport använde mappreserv", .norwegian: "Loggeksport brukte mappe-reserve",
            .danish: "Logeksport brugte mappe-reserve", .finnish: "Lokien vienti käytti kansiovaraa", .chinese: "日志导出使用了文件夹回退",
            .japanese: "ログの書き出しはフォルダーフォールバックを使用しました", .korean: "로그 내보내기가 폴더 대체를 사용함",
        ],
        .notif_app_files_zip_ready: [
            .english: "App files zip ready", .spanish: "ZIP de archivos de la app listo", .french: "ZIP des fichiers de l'app prêt",
            .german: "App-Dateien-ZIP bereit", .portuguese: "ZIP dos ficheiros da app pronto", .italian: "ZIP dei file dell'app pronto",
            .dutch: "App-bestanden-zip klaar", .russian: "ZIP с файлами приложения готов", .polish: "Plik ZIP plików aplikacji gotowy",
            .turkish: "Uygulama dosyaları ZIP'i hazır", .swedish: "App-filers zip klar", .norwegian: "App-filers zip klar",
            .danish: "App-filers zip klar", .finnish: "Sovellustiedostojen ZIP valmis", .chinese: "应用文件压缩包已就绪",
            .japanese: "アプリファイルの ZIP の準備ができました", .korean: "앱 파일 ZIP 준비됨",
        ],
        .notif_settings_backup_ready: [
            .english: "Settings backup ready", .spanish: "Copia de ajustes lista", .french: "Sauvegarde des réglages prête",
            .german: "Einstellungs-Backup bereit", .portuguese: "Cópia de definições pronta", .italian: "Backup impostazioni pronto",
            .dutch: "Instellingenback-up klaar", .russian: "Резервная копия настроек готова", .polish: "Kopia ustawień gotowa",
            .turkish: "Ayar yedeği hazır", .swedish: "Inställningssäkerhetskopia klar", .norwegian: "Sikkerhetskopi av innstillinger klar",
            .danish: "Sikkerhedskopi af indstillinger klar", .finnish: "Asetusten varmuuskopio valmis", .chinese: "设置备份已就绪",
            .japanese: "設定のバックアップの準備ができました", .korean: "설정 백업 준비됨",
        ],
        .notif_settings_restored: [
            .english: "Settings restored", .spanish: "Ajustes restaurados", .french: "Réglages restaurés",
            .german: "Einstellungen wiederhergestellt", .portuguese: "Definições restauradas", .italian: "Impostazioni ripristinate",
            .dutch: "Instellingen hersteld", .russian: "Настройки восстановлены", .polish: "Przywrócono ustawienia",
            .turkish: "Ayarlar geri yüklendi", .swedish: "Inställningar återställda", .norwegian: "Innstillinger gjenopprettet",
            .danish: "Indstillinger gendannet", .finnish: "Asetukset palautettu", .chinese: "已恢复设置",
            .japanese: "設定を復元しました", .korean: "설정 복원됨",
        ],
        .notif_settings_restore_failed: [
            .english: "Settings restore failed", .spanish: "Error al restaurar ajustes", .french: "Échec de la restauration des réglages",
            .german: "Wiederherstellung der Einstellungen fehlgeschlagen", .portuguese: "Falha ao restaurar definições", .italian: "Ripristino impostazioni non riuscito",
            .dutch: "Herstellen van instellingen mislukt", .russian: "Не удалось восстановить настройки", .polish: "Nie udało się przywrócić ustawień",
            .turkish: "Ayarlar geri yüklenemedi", .swedish: "Det gick inte att återställa inställningar", .norwegian: "Gjenoppretting av innstillinger mislyktes",
            .danish: "Gendannelse af indstillinger mislykkedes", .finnish: "Asetusten palautus epäonnistui", .chinese: "恢复设置失败",
            .japanese: "設定の復元に失敗しました", .korean: "설정 복원 실패",
        ],
        .notif_playlists_exported: [
            .english: "Playlists exported", .spanish: "Listas exportadas", .french: "Playlists exportées",
            .german: "Playlists exportiert", .portuguese: "Listas exportadas", .italian: "Playlist esportate",
            .dutch: "Afspeellijsten geëxporteerd", .russian: "Плейлисты экспортированы", .polish: "Wyeksportowano playlisty",
            .turkish: "Çalma listeleri dışa aktarıldı", .swedish: "Spellistor exporterade", .norwegian: "Spillelister eksportert",
            .danish: "Spillelister eksporteret", .finnish: "Soittolistat viety", .chinese: "已导出播放列表",
            .japanese: "プレイリストを書き出しました", .korean: "재생목록 내보냄",
        ],
        .notif_playlist_export_failed: [
            .english: "Playlist export failed", .spanish: "Error al exportar la lista", .french: "Échec de l'export de la playlist",
            .german: "Playlist-Export fehlgeschlagen", .portuguese: "Falha ao exportar a lista", .italian: "Esportazione playlist non riuscita",
            .dutch: "Afspeellijst exporteren mislukt", .russian: "Не удалось экспортировать плейлист", .polish: "Nie udało się wyeksportować playlisty",
            .turkish: "Çalma listesi dışa aktarılamadı", .swedish: "Det gick inte att exportera spellistan", .norwegian: "Eksport av spilleliste mislyktes",
            .danish: "Eksport af spilleliste mislykkedes", .finnish: "Soittolistan vienti epäonnistui", .chinese: "导出播放列表失败",
            .japanese: "プレイリストの書き出しに失敗しました", .korean: "재생목록 내보내기 실패",
        ],
        .notif_imported_playlists: [
            .english: "Imported %d playlists", .spanish: "%d listas importadas", .french: "%d playlists importées",
            .german: "%d Playlists importiert", .portuguese: "%d listas importadas", .italian: "%d playlist importate",
            .dutch: "%d afspeellijsten geïmporteerd", .russian: "Импортировано %d плейлистов", .polish: "Zaimportowano %d playlist",
            .turkish: "%d çalma listesi içe aktarıldı", .swedish: "%d spellistor importerade", .norwegian: "%d spillelister importert",
            .danish: "%d spillelister importeret", .finnish: "%d soittolistaa tuotu", .chinese: "已导入 %d 个播放列表",
            .japanese: "%d 個のプレイリストを読み込みました", .korean: "재생목록 %d개 가져옴",
        ],
        .notif_playlist_import_failed: [
            .english: "Playlist import failed", .spanish: "Error al importar la lista", .french: "Échec de l'import de la playlist",
            .german: "Playlist-Import fehlgeschlagen", .portuguese: "Falha ao importar a lista", .italian: "Importazione playlist non riuscita",
            .dutch: "Afspeellijst importeren mislukt", .russian: "Не удалось импортировать плейлист", .polish: "Nie udało się zaimportować playlisty",
            .turkish: "Çalma listesi içe aktarılamadı", .swedish: "Det gick inte att importera spellistan", .norwegian: "Import av spilleliste mislyktes",
            .danish: "Import af spilleliste mislykkedes", .finnish: "Soittolistan tuonti epäonnistui", .chinese: "导入播放列表失败",
            .japanese: "プレイリストの読み込みに失敗しました", .korean: "재생목록 가져오기 실패",
        ],
        .notif_playlist_backups_updated: [
            .english: "Playlist backups updated", .spanish: "Copias de listas actualizadas", .french: "Sauvegardes des playlists mises à jour",
            .german: "Playlist-Backups aktualisiert", .portuguese: "Cópias de listas atualizadas", .italian: "Backup delle playlist aggiornati",
            .dutch: "Afspeellijstback-ups bijgewerkt", .russian: "Резервные копии плейлистов обновлены", .polish: "Zaktualizowano kopie playlist",
            .turkish: "Çalma listesi yedekleri güncellendi", .swedish: "Spellistsäkerhetskopior uppdaterade", .norwegian: "Sikkerhetskopier av spillelister oppdatert",
            .danish: "Spilleliste-sikkerhedskopier opdateret", .finnish: "Soittolistojen varmuuskopiot päivitetty", .chinese: "已更新播放列表备份",
            .japanese: "プレイリストのバックアップを更新しました", .korean: "재생목록 백업 업데이트됨",
        ],
        .notif_playlist_restored: [
            .english: "Playlist restored", .spanish: "Lista restaurada", .french: "Playlist restaurée",
            .german: "Playlist wiederhergestellt", .portuguese: "Lista restaurada", .italian: "Playlist ripristinata",
            .dutch: "Afspeellijst hersteld", .russian: "Плейлист восстановлен", .polish: "Przywrócono playlistę",
            .turkish: "Çalma listesi geri yüklendi", .swedish: "Spellista återställd", .norwegian: "Spilleliste gjenopprettet",
            .danish: "Spilleliste gendannet", .finnish: "Soittolista palautettu", .chinese: "已恢复播放列表",
            .japanese: "プレイリストを復元しました", .korean: "재생목록 복원됨",
        ],
        .notif_playlist_restore_failed: [
            .english: "Playlist restore failed", .spanish: "Error al restaurar la lista", .french: "Échec de la restauration de la playlist",
            .german: "Playlist-Wiederherstellung fehlgeschlagen", .portuguese: "Falha ao restaurar a lista", .italian: "Ripristino playlist non riuscito",
            .dutch: "Afspeellijst herstellen mislukt", .russian: "Не удалось восстановить плейлист", .polish: "Nie udało się przywrócić playlisty",
            .turkish: "Çalma listesi geri yüklenemedi", .swedish: "Det gick inte att återställa spellistan", .norwegian: "Gjenoppretting av spilleliste mislyktes",
            .danish: "Gendannelse af spilleliste mislykkedes", .finnish: "Soittolistan palautus epäonnistui", .chinese: "恢复播放列表失败",
            .japanese: "プレイリストの復元に失敗しました", .korean: "재생목록 복원 실패",
        ],
        .notif_playlist_backup_deleted: [
            .english: "Playlist backup deleted", .spanish: "Copia de lista eliminada", .french: "Sauvegarde de playlist supprimée",
            .german: "Playlist-Backup gelöscht", .portuguese: "Cópia de lista eliminada", .italian: "Backup della playlist eliminato",
            .dutch: "Afspeellijstback-up verwijderd", .russian: "Резервная копия плейлиста удалена", .polish: "Usunięto kopię playlisty",
            .turkish: "Çalma listesi yedeği silindi", .swedish: "Spellistsäkerhetskopia raderad", .norwegian: "Sikkerhetskopi av spilleliste slettet",
            .danish: "Spilleliste-sikkerhedskopi slettet", .finnish: "Soittolistan varmuuskopio poistettu", .chinese: "已删除播放列表备份",
            .japanese: "プレイリストのバックアップを削除しました", .korean: "재생목록 백업 삭제됨",
        ],
        .notif_stats_exported: [
            .english: "Stats exported", .spanish: "Estadísticas exportadas", .french: "Stats exportées",
            .german: "Statistik exportiert", .portuguese: "Estatísticas exportadas", .italian: "Statistiche esportate",
            .dutch: "Statistieken geëxporteerd", .russian: "Статистика экспортирована", .polish: "Wyeksportowano statystyki",
            .turkish: "İstatistikler dışa aktarıldı", .swedish: "Statistik exporterad", .norwegian: "Statistikk eksportert",
            .danish: "Statistik eksporteret", .finnish: "Tilastot viety", .chinese: "已导出统计",
            .japanese: "統計を書き出しました", .korean: "통계 내보냄",
        ],
        .notif_stats_export_failed: [
            .english: "Stats export failed", .spanish: "Error al exportar estadísticas", .french: "Échec de l'export des stats",
            .german: "Statistik-Export fehlgeschlagen", .portuguese: "Falha ao exportar estatísticas", .italian: "Esportazione statistiche non riuscita",
            .dutch: "Statistieken exporteren mislukt", .russian: "Не удалось экспортировать статистику", .polish: "Nie udało się wyeksportować statystyk",
            .turkish: "İstatistikler dışa aktarılamadı", .swedish: "Det gick inte att exportera statistik", .norwegian: "Eksport av statistikk mislyktes",
            .danish: "Eksport af statistik mislykkedes", .finnish: "Tilastojen vienti epäonnistui", .chinese: "导出统计失败",
            .japanese: "統計の書き出しに失敗しました", .korean: "통계 내보내기 실패",
        ],
        .notif_listening_stats_cleared: [
            .english: "Listening stats cleared", .spanish: "Estadísticas de escucha borradas", .french: "Stats d'écoute effacées",
            .german: "Hörstatistik gelöscht", .portuguese: "Estatísticas de audição limpas", .italian: "Statistiche di ascolto cancellate",
            .dutch: "Luisterstatistieken gewist", .russian: "Статистика прослушивания очищена", .polish: "Wyczyszczono statystyki słuchania",
            .turkish: "Dinleme istatistikleri temizlendi", .swedish: "Lyssningsstatistik rensad", .norwegian: "Lyttestatistikk tømt",
            .danish: "Lyttestatistik ryddet", .finnish: "Kuuntelutilastot tyhjennetty", .chinese: "已清除收听统计",
            .japanese: "再生統計を消去しました", .korean: "청취 통계 지움",
        ],
        .notif_restart_to_apply: [
            .english: "Restart Volta to apply everywhere", .spanish: "Reinicia Volta para aplicarlo en todo", .french: "Redémarrez Volta pour tout appliquer",
            .german: "Volta neu starten, um es überall anzuwenden", .portuguese: "Reinicie o Volta para aplicar em todo o lado", .italian: "Riavvia Volta per applicare ovunque",
            .dutch: "Start Volta opnieuw om overal toe te passen", .russian: "Перезапустите Volta, чтобы применить везде", .polish: "Uruchom ponownie Volta, aby zastosować wszędzie",
            .turkish: "Her yerde uygulamak için Volta'yı yeniden başlat", .swedish: "Starta om Volta för att tillämpa överallt", .norwegian: "Start Volta på nytt for å bruke overalt",
            .danish: "Genstart Volta for at anvende overalt", .finnish: "Käynnistä Volta uudelleen ottaaksesi käyttöön kaikkialla", .chinese: "重启 Volta 以全局应用",
            .japanese: "全体に適用するには Volta を再起動してください", .korean: "전체에 적용하려면 Volta를 다시 시작하세요",
        ],

        // Settings rows
        .settings_autoplay: [
            .english: "Autoplay", .spanish: "Reproducción automática", .french: "Lecture automatique",
            .german: "Autoplay", .portuguese: "Reprodução automática", .italian: "Riproduzione automatica",
            .dutch: "Automatisch afspelen", .russian: "Автовоспроизведение", .polish: "Autoodtwarzanie",
            .turkish: "Otomatik oynatma", .swedish: "Autouppspelning", .norwegian: "Autoavspilling",
            .danish: "Automatisk afspilning", .finnish: "Automaattinen toisto", .chinese: "自动播放",
            .japanese: "自動再生", .korean: "자동 재생",
        ],
        .settings_infinite_play: [
            .english: "Infinite Play", .spanish: "Reproducción infinita", .french: "Lecture infinie",
            .german: "Endlos-Wiedergabe", .portuguese: "Reprodução infinita", .italian: "Riproduzione infinita",
            .dutch: "Oneindig afspelen", .russian: "Бесконечное воспроизведение", .polish: "Nieskończone odtwarzanie",
            .turkish: "Sonsuz oynatma", .swedish: "Oändlig uppspelning", .norwegian: "Uendelig avspilling",
            .danish: "Uendelig afspilning", .finnish: "Loputon toisto", .chinese: "无限播放",
            .japanese: "無限再生", .korean: "무한 재생",
        ],
        .settings_track_transition: [
            .english: "Track Transition", .spanish: "Transición entre pistas", .french: "Transition entre titres",
            .german: "Titelübergang", .portuguese: "Transição entre faixas", .italian: "Transizione tra brani",
            .dutch: "Overgang tussen nummers", .russian: "Переход между треками", .polish: "Przejście między utworami",
            .turkish: "Parça geçişi", .swedish: "Spårövergång", .norwegian: "Sporovergang",
            .danish: "Sporovergang", .finnish: "Kappaleen siirtymä", .chinese: "曲目过渡",
            .japanese: "曲間のトランジション", .korean: "트랙 전환",
        ],
        .settings_gapless: [
            .english: "Gapless Playback", .spanish: "Reproducción sin pausas", .french: "Lecture sans blanc",
            .german: "Lückenlose Wiedergabe", .portuguese: "Reprodução sem pausas", .italian: "Riproduzione senza pause",
            .dutch: "Naadloos afspelen", .russian: "Воспроизведение без пауз", .polish: "Odtwarzanie bez przerw",
            .turkish: "Boşluksuz oynatma", .swedish: "Sömlös uppspelning", .norwegian: "Sømløs avspilling",
            .danish: "Sømløs afspilning", .finnish: "Tauoton toisto", .chinese: "无缝播放",
            .japanese: "ギャップレス再生", .korean: "갭리스 재생",
        ],
        .settings_shuffle_default: [
            .english: "Shuffle by Default", .spanish: "Aleatorio por defecto", .french: "Lecture aléatoire par défaut",
            .german: "Standardmäßig zufällig", .portuguese: "Aleatório por predefinição", .italian: "Casuale per impostazione",
            .dutch: "Standaard shuffle", .russian: "Перемешивать по умолчанию", .polish: "Domyślnie losowo",
            .turkish: "Varsayılan karıştır", .swedish: "Blanda som standard", .norwegian: "Bland som standard",
            .danish: "Bland som standard", .finnish: "Sekoita oletuksena", .chinese: "默认随机播放",
            .japanese: "デフォルトでシャッフル", .korean: "기본 셔플",
        ],
        .settings_artwork_zoom: [
            .english: "Artwork Zoom on Play", .spanish: "Zoom de carátula al reproducir", .french: "Zoom sur la pochette à la lecture",
            .german: "Cover-Zoom bei Wiedergabe", .portuguese: "Zoom da capa ao reproduzir", .italian: "Zoom copertina alla riproduzione",
            .dutch: "Albumhoes inzoomen bij afspelen", .russian: "Увеличение обложки при воспроизведении", .polish: "Powiększenie okładki przy odtwarzaniu",
            .turkish: "Çalarken kapak yakınlaştırma", .swedish: "Omslagszoom vid uppspelning", .norwegian: "Omslagszoom ved avspilling",
            .danish: "Omslagszoom ved afspilning", .finnish: "Kansikuvan zoomaus toistettaessa", .chinese: "播放时封面缩放",
            .japanese: "再生時にアートワークをズーム", .korean: "재생 시 아트워크 확대",
        ],
        .settings_resume_interruption: [
            .english: "Resume After Interruption", .spanish: "Reanudar tras interrupción", .french: "Reprendre après interruption",
            .german: "Nach Unterbrechung fortsetzen", .portuguese: "Retomar após interrupção", .italian: "Riprendi dopo interruzione",
            .dutch: "Hervatten na onderbreking", .russian: "Возобновлять после прерывания", .polish: "Wznów po przerwaniu",
            .turkish: "Kesintiden sonra devam et", .swedish: "Återuppta efter avbrott", .norwegian: "Gjenoppta etter avbrudd",
            .danish: "Genoptag efter afbrydelse", .finnish: "Jatka keskeytyksen jälkeen", .chinese: "中断后继续播放",
            .japanese: "中断後に再開", .korean: "중단 후 다시 재생",
        ],
        .settings_equalizer: [
            .english: "Equalizer", .spanish: "Ecualizador", .french: "Égaliseur",
            .german: "Equalizer", .portuguese: "Equalizador", .italian: "Equalizzatore",
            .dutch: "Equalizer", .russian: "Эквалайзер", .polish: "Korektor",
            .turkish: "Ekolayzer", .swedish: "Equalizer", .norwegian: "Equalizer",
            .danish: "Equalizer", .finnish: "Taajuuskorjain", .chinese: "均衡器",
            .japanese: "イコライザ", .korean: "이퀄라이저",
        ],
        .settings_volume_normalization: [
            .english: "Volume Normalization", .spanish: "Normalización de volumen", .french: "Normalisation du volume",
            .german: "Lautstärke-Normalisierung", .portuguese: "Normalização de volume", .italian: "Normalizzazione del volume",
            .dutch: "Volumenormalisatie", .russian: "Нормализация громкости", .polish: "Normalizacja głośności",
            .turkish: "Ses normalleştirme", .swedish: "Volymnormalisering", .norwegian: "Volumnormalisering",
            .danish: "Volumennormalisering", .finnish: "Äänenvoimakkuuden normalisointi", .chinese: "音量标准化",
            .japanese: "音量の正規化", .korean: "음량 정규화",
        ],
        .settings_mono_audio: [
            .english: "Mono Audio", .spanish: "Audio mono", .french: "Audio mono",
            .german: "Mono-Audio", .portuguese: "Áudio mono", .italian: "Audio mono",
            .dutch: "Mono-audio", .russian: "Моно-звук", .polish: "Dźwięk mono",
            .turkish: "Mono ses", .swedish: "Monoljud", .norwegian: "Monolyd",
            .danish: "Monolyd", .finnish: "Monoääni", .chinese: "单声道",
            .japanese: "モノラル音声", .korean: "모노 오디오",
        ],
        .settings_spatial_widener: [
            .english: "3D Spatial Widener", .spanish: "Ampliador espacial 3D", .french: "Élargisseur spatial 3D",
            .german: "3D-Raumerweiterung", .portuguese: "Ampliador espacial 3D", .italian: "Ampliatore spaziale 3D",
            .dutch: "3D ruimtelijke verbreder", .russian: "3D-расширение", .polish: "Poszerzacz przestrzeni 3D",
            .turkish: "3D uzamsal genişletici", .swedish: "3D-rumsvidgare", .norwegian: "3D-romutvider",
            .danish: "3D-rumudvider", .finnish: "3D-tilan laajennin", .chinese: "3D 空间扩展",
            .japanese: "3D 空間ワイドナー", .korean: "3D 공간 확장",
        ],
        .settings_wifi_quality: [
            .english: "Wi-Fi Quality", .spanish: "Calidad por Wi-Fi", .french: "Qualité en Wi-Fi",
            .german: "WLAN-Qualität", .portuguese: "Qualidade no Wi-Fi", .italian: "Qualità su Wi-Fi",
            .dutch: "Wifi-kwaliteit", .russian: "Качество по Wi-Fi", .polish: "Jakość przez Wi-Fi",
            .turkish: "Wi-Fi kalitesi", .swedish: "Wi-Fi-kvalitet", .norwegian: "Wi-Fi-kvalitet",
            .danish: "Wi-Fi-kvalitet", .finnish: "Wi-Fi-laatu", .chinese: "Wi-Fi 音质",
            .japanese: "Wi-Fi 時の音質", .korean: "Wi-Fi 음질",
        ],
        .settings_cellular_quality: [
            .english: "Cellular Quality", .spanish: "Calidad con datos móviles", .french: "Qualité en cellulaire",
            .german: "Mobilfunk-Qualität", .portuguese: "Qualidade em dados móveis", .italian: "Qualità su cellulare",
            .dutch: "Mobiele kwaliteit", .russian: "Качество по моб. сети", .polish: "Jakość przez sieć komórkową",
            .turkish: "Hücresel kalite", .swedish: "Mobil kvalitet", .norwegian: "Mobilkvalitet",
            .danish: "Mobilkvalitet", .finnish: "Mobiilidatan laatu", .chinese: "蜂窝网络音质",
            .japanese: "モバイル通信時の音質", .korean: "셀룰러 음질",
        ],
        .settings_download_quality: [
            .english: "Download Quality", .spanish: "Calidad de descarga", .french: "Qualité de téléchargement",
            .german: "Download-Qualität", .portuguese: "Qualidade de transferência", .italian: "Qualità di download",
            .dutch: "Downloadkwaliteit", .russian: "Качество загрузки", .polish: "Jakość pobierania",
            .turkish: "İndirme kalitesi", .swedish: "Nedladdningskvalitet", .norwegian: "Nedlastingskvalitet",
            .danish: "Downloadkvalitet", .finnish: "Latauksen laatu", .chinese: "下载音质",
            .japanese: "ダウンロードの音質", .korean: "다운로드 음질",
        ],
        .settings_transcoding_format: [
            .english: "Transcoding Format", .spanish: "Formato de transcodificación", .french: "Format de transcodage",
            .german: "Transcoding-Format", .portuguese: "Formato de transcodificação", .italian: "Formato di transcodifica",
            .dutch: "Transcoderingsformaat", .russian: "Формат перекодирования", .polish: "Format transkodowania",
            .turkish: "Yeniden kodlama biçimi", .swedish: "Omkodningsformat", .norwegian: "Transkodingsformat",
            .danish: "Transkodningsformat", .finnish: "Transkoodausmuoto", .chinese: "转码格式",
            .japanese: "トランスコード形式", .korean: "트랜스코딩 형식",
        ],
        .settings_download_mode: [
            .english: "Download Mode", .spanish: "Modo de descarga", .french: "Mode de téléchargement",
            .german: "Download-Modus", .portuguese: "Modo de transferência", .italian: "Modalità di download",
            .dutch: "Downloadmodus", .russian: "Режим загрузки", .polish: "Tryb pobierania",
            .turkish: "İndirme modu", .swedish: "Nedladdningsläge", .norwegian: "Nedlastingsmodus",
            .danish: "Downloadtilstand", .finnish: "Lataustila", .chinese: "下载模式",
            .japanese: "ダウンロードモード", .korean: "다운로드 모드",
        ],
        .settings_download_speed_limit: [
            .english: "Download Speed Limit", .spanish: "Límite de velocidad de descarga", .french: "Limite de vitesse de téléchargement",
            .german: "Download-Geschwindigkeitslimit", .portuguese: "Limite de velocidade de transferência", .italian: "Limite di velocità download",
            .dutch: "Downloadsnelheidslimiet", .russian: "Ограничение скорости загрузки", .polish: "Limit prędkości pobierania",
            .turkish: "İndirme hızı sınırı", .swedish: "Hastighetsgräns för nedladdning", .norwegian: "Hastighetsgrense for nedlasting",
            .danish: "Hastighedsgrænse for download", .finnish: "Latausnopeuden raja", .chinese: "下载速度限制",
            .japanese: "ダウンロード速度制限", .korean: "다운로드 속도 제한",
        ],
        .settings_download_storage_cap: [
            .english: "Download Storage Cap", .spanish: "Límite de espacio", .french: "Limite de stockage des téléchargements",
            .german: "Speicherlimit für Downloads", .portuguese: "Limite de armazenamento de transferências", .italian: "Limite di spazio per i download",
            .dutch: "Opslaglimiet voor downloads", .russian: "Лимит хранилища для загрузок", .polish: "Limit pamięci na pobrania",
            .turkish: "İndirme depolama sınırı", .swedish: "Lagringsgräns för nedladdningar", .norwegian: "Lagringsgrense for nedlastinger",
            .danish: "Lagringsgrænse for downloads", .finnish: "Latausten tallennusraja", .chinese: "下载存储上限",
            .japanese: "ダウンロードの保存上限", .korean: "다운로드 저장 한도",
        ],
        .settings_auto_evict: [
            .english: "Auto-Evict Oldest", .spanish: "Eliminar las más antiguas", .french: "Supprimer les plus anciens",
            .german: "Älteste automatisch entfernen", .portuguese: "Remover as mais antigas", .italian: "Rimuovi i più vecchi",
            .dutch: "Oudste automatisch verwijderen", .russian: "Удалять старые автоматически", .polish: "Automatycznie usuwaj najstarsze",
            .turkish: "En eskileri otomatik sil", .swedish: "Ta bort äldsta automatiskt", .norwegian: "Fjern eldste automatisk",
            .danish: "Fjern ældste automatisk", .finnish: "Poista vanhimmat automaattisesti", .chinese: "自动清除最旧的",
            .japanese: "古いものを自動削除", .korean: "오래된 항목 자동 삭제",
        ],
    ]
}
