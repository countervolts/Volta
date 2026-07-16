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
    case error_plex_no_servers
    case error_plex_access_denied
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
    case appearance_explicit_badge
    case appearance_live_artwork
    case appearance_stylized_cover
    case appearance_song_artwork_lists
    case appearance_long_track_titles
    case track_titles_truncate
    case track_titles_sliding
    case track_titles_new_line
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
    case theme_system
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

    // Browse screens (Search / Artist / Album / Queue / Lyrics)
    case search_placeholder
    case search_recent
    case search_no_results                // "%@" = query
    case search_from_lyrics
    case media_albums
    case media_genres
    case artist_about                     // "%@" = artist name
    case action_more
    case action_add
    case album_disc                       // "%d" = disc number
    case album_add_to_playlist_q
    case album_add_song_confirm           // "%@" = song, "%@" = playlist
    case queue_continue_playing
    case lyrics_none
    case search_prompt
    case search_browse_genres
    case search_genre_mix_subtitle        // "%@" = genre name
    case media_album_count                // "%d" = album count

    // Artist / Album detail
    case toast_added_to                   // "%@" = playlist name
    case section_top_songs
    case section_liked_songs
    case section_appeared_on
    case section_similar_artists
    case stat_total_plays
    case stat_active_since
    case stat_years_active
    case a11y_see_all                     // "%@" = section title

    // Album detail: audio quality + info popover
    case action_less
    case quality_hires_lossless
    case quality_lossless
    case quality_lossy
    case album_more_by                    // "%@" = artist
    case album_quality_lossy_title
    case album_quality_hires_title
    case album_quality_lossless_title
    case album_quality_mixed_title
    case album_quality_lossy_desc         // "%d" = track count
    case album_quality_hires_desc         // "%d" = track count
    case album_quality_lossless_desc      // "%d" = track count
    case album_quality_mixed_desc         // "%d" lossless, "%d" total
    case detail_formats
    case detail_sample_rates
    case detail_bit_depths
    case detail_hires_tracks
    case detail_x_of_y                    // "%d" of "%d"
    case detail_bit_value                 // "%d" = bit depth

    // Queue
    case queue_repeat
    case queue_repeat_one

    // Library
    case library_search_prompt
    case library_folders
    case library_source
    case library_sort_by
    case library_all_genres
    case library_never_played
    case library_clear_filters
    case library_all_folders
    case library_select_all
    case library_deselect_all
    case library_add_n_songs              // "%d" = song count
    case action_queue
    case media_playlist
    case library_source_server
    case library_source_downloaded
    case sort_name
    case sort_most_played
    case playlists_none_yet

    // Playlists screen
    case playlists_search_prompt
    case playlists_count                  // "%d" = count
    case playlist_delete_q
    case playlist_delete_named            // "%@" = name
    case playlist_delete_msg              // "%@" = name
    case smart_delete_q
    case smart_delete_msg                 // "%@" = name
    case folder_delete_q
    case folder_delete_msg                // "%@" = name
    case playlist_pin
    case playlist_unpin
    case folder_add_to
    case folder_remove_from
    case media_folder
    case folder_empty
    case action_clear_selection
    case search_x                         // "%@" = scope
    case create_type
    case create_playlist_name_ph
    case create_folder_name_ph
    case create_new_playlist_title
    case action_create
    case name_exists_title
    case smart_songs_rule                 // "%d" songs, "%@" rule summary
    // Smart playlist editor
    case smart_name_ph
    case smart_desc
    case smart_section_rules
    case smart_match
    case smart_search_ph
    case smart_artist_ph
    case smart_album_ph
    case smart_any_genre
    case smart_section_filters
    case smart_min_year_ph
    case smart_max_year_ph
    case smart_min_plays_ph
    case smart_max_plays_ph
    case smart_never_played_only
    case smart_lossless_only
    case smart_hires_only
    case smart_downloaded_only
    case smart_taste
    case smart_section_mix
    case smart_sort
    case smart_limit                      // "%d" = limit
    case smart_matching_now               // "%d" = count
    case smart_any
    // Smart playlist enum cases
    case create_kind_custom
    case create_kind_smart
    case smart_match_all
    case smart_match_any
    case smart_taste_loved
    case smart_taste_not_disliked
    case smart_taste_disliked
    case smart_sort_title
    case smart_sort_newest
    case smart_sort_oldest
    case smart_sort_least_played
    case smart_sort_random
    case smart_mix
    case toast_added_count_to             // "%d" count, "%@" playlist
    case toast_playing_n_next             // "%d" = count
    case toast_added_n_to_queue           // "%d" = count
    case toast_downloading_n              // "%d" = count
    case smart_n_selected                 // "%d" = count
    case dup_playlist                     // "%@" = name
    case dup_smart                        // "%@" = name
    case dup_folder                       // "%@" = name

    // Playlist detail / edit
    case playlist_edit_title
    case playlist_add_description
    case playlist_remove_from

    // Now Playing + sleep timer + audio signal path
    case player_mixing
    case player_not_playing
    case sleep_cancel_end_of_track
    case sleep_cancel_timer
    case sleep_minutes                    // "%d" = minutes
    case sleep_end_of_track
    case action_yes
    case action_no
    case action_on
    case action_off
    case media_equalizer
    case detail_bitrate
    case detail_sample_rate
    case detail_bit_depth
    case signal_lossless_audio
    case signal_output
    case signal_system_output
    case signal_path_title
    case signal_source_file
    case signal_server_stream
    case signal_transcoding
    case signal_original
    case signal_wifi_quality
    case signal_cellular_quality
    case signal_same_as_wifi
    case signal_app_processing
    case signal_volume_norm
    case signal_port_type
    case signal_output_sample_rate
    case signal_output_channels
    case signal_result
    case signal_badge
    case signal_not_lossless
    case signal_why
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
        .error_plex_no_servers: [
            .english: "No Plex Media Server is available for this Plex account.",
        ],
        .error_plex_access_denied: [
            .english: "Plex sign-in succeeded, but this account could not access an available Plex Media Server.",
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
        .appearance_explicit_badge: [
            .english: "Show Explicit Badge", .spanish: "Mostrar insignia de contenido explícito", .french: "Afficher le badge explicite",
            .german: "Explicit-Abzeichen anzeigen", .portuguese: "Mostrar selo de conteúdo explícito", .italian: "Mostra badge esplicito",
            .dutch: "Explicit-badge tonen", .russian: "Показывать значок Explicit", .polish: "Pokaż plakietkę Explicit",
            .turkish: "Explicit rozetini göster", .swedish: "Visa explicit-märke", .norwegian: "Vis explicit-merke",
            .danish: "Vis explicit-mærke", .finnish: "Näytä explicit-merkki", .chinese: "显示限制级标记",
            .japanese: "Explicitバッジを表示", .korean: "유해 콘텐츠 배지 표시",
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
        .appearance_long_track_titles: [
            .english: "Long Track Titles", .spanish: "Títulos largos de canciones", .french: "Titres de morceaux longs",
            .german: "Lange Songtitel", .portuguese: "Títulos longos das faixas", .italian: "Titoli lunghi dei brani",
            .dutch: "Lange tracktitels", .russian: "Длинные названия треков", .polish: "Długie tytuły utworów",
            .turkish: "Uzun parça adları", .swedish: "Långa låttitlar", .norwegian: "Lange sangtitler",
            .danish: "Lange sangtitler", .finnish: "Pitkät kappaleiden nimet", .chinese: "长歌曲标题",
            .japanese: "長い曲名", .korean: "긴 곡 제목",
        ],
        .track_titles_truncate: [
            .english: "Truncate", .spanish: "Truncar", .french: "Tronquer", .german: "Kürzen",
            .portuguese: "Truncar", .italian: "Tronca", .dutch: "Afkappen", .russian: "Обрезать",
            .polish: "Skróć", .turkish: "Kısalt", .swedish: "Korta av", .norwegian: "Forkort",
            .danish: "Forkort", .finnish: "Lyhennä", .chinese: "截断", .japanese: "省略", .korean: "말줄임",
        ],
        .track_titles_sliding: [
            .english: "Sliding", .spanish: "Deslizante", .french: "Défilement", .german: "Lauftext",
            .portuguese: "Deslizante", .italian: "Scorrimento", .dutch: "Schuivend", .russian: "Прокрутка",
            .polish: "Przewijanie", .turkish: "Kayan", .swedish: "Rullande", .norwegian: "Rullende",
            .danish: "Rullende", .finnish: "Vierivä", .chinese: "滚动", .japanese: "スクロール", .korean: "스크롤",
        ],
        .track_titles_new_line: [
            .english: "New Line", .spanish: "Nueva línea", .french: "Nouvelle ligne", .german: "Neue Zeile",
            .portuguese: "Nova linha", .italian: "Nuova riga", .dutch: "Nieuwe regel", .russian: "Новая строка",
            .polish: "Nowy wiersz", .turkish: "Yeni satır", .swedish: "Ny rad", .norwegian: "Ny linje",
            .danish: "Ny linje", .finnish: "Uusi rivi", .chinese: "换行", .japanese: "改行", .korean: "줄바꿈",
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
        .theme_system: [
            .english: "System", .spanish: "Sistema", .french: "Système", .german: "System",
            .portuguese: "Sistema", .italian: "Sistema", .dutch: "Systeem", .russian: "Системная",
            .polish: "Systemowy", .turkish: "Sistem", .swedish: "System", .norwegian: "System",
            .danish: "System", .finnish: "Järjestelmä", .chinese: "系统", .japanese: "システム", .korean: "시스템",
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

        // MARK: Browse screens (Search / Artist / Album / Queue / Lyrics)
        .search_placeholder: tr(
            en: "Search your library", es: "Busca en tu biblioteca", fr: "Rechercher dans votre bibliothèque",
            de: "Mediathek durchsuchen", pt: "Pesquisar na biblioteca", it: "Cerca nella libreria",
            nl: "Zoek in je bibliotheek", ru: "Поиск в медиатеке", pl: "Szukaj w bibliotece",
            tr: "Kitaplığında ara", sv: "Sök i biblioteket", nb: "Søk i biblioteket",
            da: "Søg i biblioteket", fi: "Hae kirjastosta", zh: "搜索你的音乐库", ja: "ライブラリを検索", ko: "라이브러리 검색"
        ),
        .search_recent: tr(
            en: "Recent", es: "Recientes", fr: "Récents", de: "Zuletzt", pt: "Recentes", it: "Recenti",
            nl: "Recent", ru: "Недавние", pl: "Ostatnie", tr: "Son aramalar", sv: "Senaste", nb: "Nylig",
            da: "Seneste", fi: "Viimeisimmät", zh: "最近", ja: "最近", ko: "최근"
        ),
        .search_no_results: tr(
            en: "No results for \"%@\"", es: "Sin resultados para «%@»", fr: "Aucun résultat pour « %@ »",
            de: "Keine Ergebnisse für „%@“", pt: "Nenhum resultado para “%@”", it: "Nessun risultato per “%@”",
            nl: "Geen resultaten voor “%@”", ru: "Нет результатов для «%@»", pl: "Brak wyników dla „%@”",
            tr: "“%@” için sonuç yok", sv: "Inga resultat för ”%@”", nb: "Ingen resultater for «%@»",
            da: "Ingen resultater for “%@”", fi: "Ei tuloksia haulle ”%@”", zh: "没有“%@”的结果", ja: "「%@」の結果がありません", ko: "“%@” 검색 결과 없음"
        ),
        .search_from_lyrics: tr(
            en: "From Lyrics", es: "Por letras", fr: "Dans les paroles", de: "Aus Songtexten", pt: "Nas letras", it: "Dai testi",
            nl: "Uit songteksten", ru: "По тексту", pl: "Z tekstów", tr: "Şarkı sözlerinden", sv: "Från låttexter", nb: "Fra sangtekster",
            da: "Fra sangtekster", fi: "Sanoituksista", zh: "来自歌词", ja: "歌詞から", ko: "가사에서"
        ),
        .media_albums: tr(
            en: "Albums", es: "Álbumes", fr: "Albums", de: "Alben", pt: "Álbuns", it: "Album",
            nl: "Albums", ru: "Альбомы", pl: "Albumy", tr: "Albümler", sv: "Album", nb: "Album",
            da: "Album", fi: "Albumit", zh: "专辑", ja: "アルバム", ko: "앨범"
        ),
        .media_genres: tr(
            en: "Genres", es: "Géneros", fr: "Genres", de: "Genres", pt: "Géneros", it: "Generi",
            nl: "Genres", ru: "Жанры", pl: "Gatunki", tr: "Türler", sv: "Genrer", nb: "Sjangere",
            da: "Genrer", fi: "Genret", zh: "流派", ja: "ジャンル", ko: "장르"
        ),
        .artist_about: tr(
            en: "About %@", es: "Acerca de %@", fr: "À propos de %@", de: "Über %@", pt: "Sobre %@", it: "Informazioni su %@",
            nl: "Over %@", ru: "О %@", pl: "O %@", tr: "%@ hakkında", sv: "Om %@", nb: "Om %@",
            da: "Om %@", fi: "Tietoja: %@", zh: "关于 %@", ja: "%@について", ko: "%@ 정보"
        ),
        .action_more: tr(
            en: "More", es: "Más", fr: "Plus", de: "Mehr", pt: "Mais", it: "Altro",
            nl: "Meer", ru: "Ещё", pl: "Więcej", tr: "Daha fazla", sv: "Mer", nb: "Mer",
            da: "Mere", fi: "Lisää", zh: "更多", ja: "もっと見る", ko: "더 보기"
        ),
        .action_add: tr(
            en: "Add", es: "Añadir", fr: "Ajouter", de: "Hinzufügen", pt: "Adicionar", it: "Aggiungi",
            nl: "Toevoegen", ru: "Добавить", pl: "Dodaj", tr: "Ekle", sv: "Lägg till", nb: "Legg til",
            da: "Tilføj", fi: "Lisää", zh: "添加", ja: "追加", ko: "추가"
        ),
        .album_disc: tr(
            en: "Disc %d", es: "Disco %d", fr: "Disque %d", de: "CD %d", pt: "Disco %d", it: "Disco %d",
            nl: "Schijf %d", ru: "Диск %d", pl: "Płyta %d", tr: "Disk %d", sv: "Skiva %d", nb: "Plate %d",
            da: "Disk %d", fi: "Levy %d", zh: "碟 %d", ja: "ディスク %d", ko: "디스크 %d"
        ),
        .album_add_to_playlist_q: tr(
            en: "Add to playlist?", es: "¿Añadir a la lista?", fr: "Ajouter à la playlist ?", de: "Zur Playlist hinzufügen?",
            pt: "Adicionar à lista?", it: "Aggiungere alla playlist?", nl: "Toevoegen aan afspeellijst?", ru: "Добавить в плейлист?",
            pl: "Dodać do playlisty?", tr: "Çalma listesine eklensin mi?", sv: "Lägg till i spellista?", nb: "Legg til i spilleliste?",
            da: "Føj til playliste?", fi: "Lisätäänkö soittolistalle?", zh: "添加到播放列表？", ja: "プレイリストに追加しますか？", ko: "재생목록에 추가할까요?"
        ),
        .album_add_song_confirm: tr(
            en: "Add \"%@\" to \"%@\"?", es: "¿Añadir «%@» a «%@»?", fr: "Ajouter « %@ » à « %@ » ?", de: "„%@“ zu „%@“ hinzufügen?",
            pt: "Adicionar “%@” a “%@”?", it: "Aggiungere “%@” a “%@”?", nl: "“%@” toevoegen aan “%@”?", ru: "Добавить «%@» в «%@»?",
            pl: "Dodać „%@” do „%@”?", tr: "“%@” şu listeye eklensin mi: “%@”?", sv: "Lägg till ”%@” i ”%@”?", nb: "Legg til «%@» i «%@»?",
            da: "Føj “%@” til “%@”?", fi: "Lisätäänkö ”%@” listalle ”%@”?", zh: "将“%@”添加到“%@”？", ja: "「%@」を「%@」に追加しますか？", ko: "“%@”을(를) “%@”에 추가할까요?"
        ),
        .queue_continue_playing: tr(
            en: "Continue Playing", es: "Seguir reproduciendo", fr: "Continuer la lecture", de: "Weiter abspielen",
            pt: "Continuar a reprodução", it: "Continua la riproduzione", nl: "Verder afspelen", ru: "Продолжить воспроизведение",
            pl: "Kontynuuj odtwarzanie", tr: "Çalmaya devam et", sv: "Fortsätt spela", nb: "Fortsett avspilling",
            da: "Fortsæt afspilning", fi: "Jatka toistoa", zh: "继续播放", ja: "再生を続ける", ko: "계속 재생"
        ),
        .lyrics_none: tr(
            en: "No lyrics available", es: "No hay letra disponible", fr: "Aucune parole disponible", de: "Kein Songtext verfügbar",
            pt: "Nenhuma letra disponível", it: "Nessun testo disponibile", nl: "Geen songtekst beschikbaar", ru: "Текст недоступен",
            pl: "Brak tekstu", tr: "Şarkı sözü yok", sv: "Inga låttexter tillgängliga", nb: "Ingen sangtekst tilgjengelig",
            da: "Ingen sangtekst tilgængelig", fi: "Sanoituksia ei saatavilla", zh: "暂无歌词", ja: "歌詞がありません", ko: "가사 없음"
        ),
        .search_prompt: tr(
            en: "Albums, Artists, Songs, Lyrics", es: "Álbumes, artistas, canciones, letras", fr: "Albums, artistes, titres, paroles",
            de: "Alben, Künstler, Songs, Songtexte", pt: "Álbuns, artistas, músicas, letras", it: "Album, artisti, brani, testi",
            nl: "Albums, artiesten, nummers, songteksten", ru: "Альбомы, артисты, песни, тексты", pl: "Albumy, wykonawcy, utwory, teksty",
            tr: "Albümler, sanatçılar, şarkılar, sözler", sv: "Album, artister, låtar, låttexter", nb: "Album, artister, låter, sangtekster",
            da: "Album, kunstnere, sange, sangtekster", fi: "Albumit, artistit, kappaleet, sanoitukset", zh: "专辑、艺人、歌曲、歌词", ja: "アルバム、アーティスト、曲、歌詞", ko: "앨범, 아티스트, 곡, 가사"
        ),
        .search_browse_genres: tr(
            en: "Browse Genres", es: "Explorar géneros", fr: "Parcourir les genres", de: "Genres durchsuchen",
            pt: "Explorar géneros", it: "Sfoglia i generi", nl: "Genres verkennen", ru: "Обзор жанров",
            pl: "Przeglądaj gatunki", tr: "Türlere göz at", sv: "Bläddra bland genrer", nb: "Bla i sjangere",
            da: "Gennemse genrer", fi: "Selaa genrejä", zh: "浏览流派", ja: "ジャンルを見る", ko: "장르 둘러보기"
        ),
        .search_genre_mix_subtitle: tr(
            en: "Made from %@ songs", es: "Creada con canciones de %@", fr: "Composé de titres %@", de: "Aus %@-Songs",
            pt: "Feito com músicas de %@", it: "Creato con brani %@", nl: "Samengesteld uit %@-nummers", ru: "Из песен в жанре %@",
            pl: "Z utworów %@", tr: "%@ şarkılarından oluşur", sv: "Skapad av %@-låtar", nb: "Laget av %@-låter",
            da: "Lavet af %@-sange", fi: "Koottu %@-kappaleista", zh: "由%@歌曲组成", ja: "%@の曲で構成", ko: "%@ 곡으로 구성"
        ),
        .media_album_count: tr(
            en: "%d albums", es: "%d álbumes", fr: "%d albums", de: "%d Alben", pt: "%d álbuns", it: "%d album",
            nl: "%d albums", ru: "%d альбомов", pl: "%d albumów", tr: "%d albüm", sv: "%d album", nb: "%d album",
            da: "%d album", fi: "%d albumia", zh: "%d 张专辑", ja: "%d 枚のアルバム", ko: "앨범 %d개"
        ),

        // MARK: Artist / Album detail
        .toast_added_to: tr(
            en: "Added to %@", es: "Añadido a %@", fr: "Ajouté à %@", de: "Zu %@ hinzugefügt", pt: "Adicionado a %@", it: "Aggiunto a %@",
            nl: "Toegevoegd aan %@", ru: "Добавлено в %@", pl: "Dodano do %@", tr: "%@ listesine eklendi", sv: "Tillagd i %@", nb: "Lagt til i %@",
            da: "Føjet til %@", fi: "Lisätty: %@", zh: "已添加到%@", ja: "%@に追加しました", ko: "%@에 추가됨"
        ),
        .section_top_songs: tr(
            en: "Top Songs", es: "Mejores canciones", fr: "Titres populaires", de: "Top-Songs", pt: "Melhores músicas", it: "Brani migliori",
            nl: "Topnummers", ru: "Популярные песни", pl: "Najlepsze utwory", tr: "En iyi şarkılar", sv: "Topplåtar", nb: "Topplåter",
            da: "Topnumre", fi: "Suosituimmat kappaleet", zh: "热门歌曲", ja: "人気の曲", ko: "인기 곡"
        ),
        .section_liked_songs: tr(
            en: "Liked Songs", es: "Canciones favoritas", fr: "Titres aimés", de: "Gemochte Songs", pt: "Músicas curtidas", it: "Brani preferiti",
            nl: "Favoriete nummers", ru: "Понравившиеся", pl: "Polubione utwory", tr: "Beğenilen şarkılar", sv: "Gillade låtar", nb: "Likede låter",
            da: "Foretrukne numre", fi: "Tykätyt kappaleet", zh: "喜欢的歌曲", ja: "お気に入りの曲", ko: "좋아요 표시한 곡"
        ),
        .section_appeared_on: tr(
            en: "Appeared On", es: "Apareció en", fr: "Apparaît sur", de: "Mitgewirkt auf", pt: "Apareceu em", it: "Appare in",
            nl: "Verschenen op", ru: "Участие в", pl: "Wystąpił na", tr: "Yer aldığı albümler", sv: "Medverkar på", nb: "Medvirker på",
            da: "Medvirker på", fi: "Esiintyy albumeilla", zh: "参与专辑", ja: "参加作品", ko: "참여 앨범"
        ),
        .section_similar_artists: tr(
            en: "Similar Artists", es: "Artistas similares", fr: "Artistes similaires", de: "Ähnliche Künstler", pt: "Artistas semelhantes", it: "Artisti simili",
            nl: "Vergelijkbare artiesten", ru: "Похожие артисты", pl: "Podobni wykonawcy", tr: "Benzer sanatçılar", sv: "Liknande artister", nb: "Lignende artister",
            da: "Lignende kunstnere", fi: "Samankaltaiset artistit", zh: "相似艺人", ja: "似たアーティスト", ko: "비슷한 아티스트"
        ),
        .stat_total_plays: tr(
            en: "Total Plays", es: "Reproducciones totales", fr: "Lectures totales", de: "Wiedergaben gesamt", pt: "Reproduções totais", it: "Riproduzioni totali",
            nl: "Totaal afgespeeld", ru: "Всего прослушиваний", pl: "Łączne odtworzenia", tr: "Toplam çalma", sv: "Totalt antal spelningar", nb: "Totalt antall avspillinger",
            da: "Afspilninger i alt", fi: "Toistoja yhteensä", zh: "总播放次数", ja: "総再生回数", ko: "총 재생 횟수"
        ),
        .stat_active_since: tr(
            en: "Active Since", es: "Activo desde", fr: "Actif depuis", de: "Aktiv seit", pt: "Ativo desde", it: "Attivo dal",
            nl: "Actief sinds", ru: "Активен с", pl: "Aktywny od", tr: "Şu tarihten beri aktif", sv: "Aktiv sedan", nb: "Aktiv siden",
            da: "Aktiv siden", fi: "Aktiivinen vuodesta", zh: "活跃始于", ja: "活動開始", ko: "활동 시작"
        ),
        .stat_years_active: tr(
            en: "Years Active", es: "Años activo", fr: "Années d'activité", de: "Aktive Jahre", pt: "Anos ativo", it: "Anni di attività",
            nl: "Jaren actief", ru: "Годы активности", pl: "Lata aktywności", tr: "Aktif yıllar", sv: "Aktiva år", nb: "Aktive år",
            da: "Aktive år", fi: "Aktiiviset vuodet", zh: "活跃年份", ja: "活動年数", ko: "활동 연수"
        ),
        .a11y_see_all: tr(
            en: "See all %@", es: "Ver todo: %@", fr: "Voir tout : %@", de: "Alle anzeigen: %@", pt: "Ver tudo: %@", it: "Vedi tutti: %@",
            nl: "Alles tonen: %@", ru: "Показать все: %@", pl: "Zobacz wszystko: %@", tr: "Tümünü gör: %@", sv: "Visa alla: %@", nb: "Se alle: %@",
            da: "Se alle: %@", fi: "Näytä kaikki: %@", zh: "查看全部%@", ja: "%@をすべて表示", ko: "%@ 모두 보기"
        ),

        // MARK: Album detail: audio quality + info popover
        .action_less: tr(
            en: "Less", es: "Menos", fr: "Moins", de: "Weniger", pt: "Menos", it: "Meno",
            nl: "Minder", ru: "Свернуть", pl: "Mniej", tr: "Daha az", sv: "Mindre", nb: "Mindre",
            da: "Mindre", fi: "Vähemmän", zh: "收起", ja: "閉じる", ko: "접기"
        ),
        .quality_hires_lossless: tr(
            en: "Hi-Res Lossless", es: "Hi-Res sin pérdida", fr: "Hi-Res Lossless", de: "Hi-Res Lossless", pt: "Hi-Res sem perdas", it: "Hi-Res Lossless",
            nl: "Hi-Res Lossless", ru: "Hi-Res без потерь", pl: "Hi-Res bezstratny", tr: "Hi-Res Kayıpsız", sv: "Hi-Res förlustfri", nb: "Hi-Res tapsfri",
            da: "Hi-Res tabsfri", fi: "Hi-Res häviötön", zh: "高解析度无损", ja: "ハイレゾロスレス", ko: "고해상도 무손실"
        ),
        .quality_lossless: tr(
            en: "Lossless", es: "Sin pérdida", fr: "Lossless", de: "Verlustfrei", pt: "Sem perdas", it: "Lossless",
            nl: "Lossless", ru: "Без потерь", pl: "Bezstratny", tr: "Kayıpsız", sv: "Förlustfri", nb: "Tapsfri",
            da: "Tabsfri", fi: "Häviötön", zh: "无损", ja: "ロスレス", ko: "무손실"
        ),
        .quality_lossy: tr(
            en: "Lossy", es: "Con pérdida", fr: "Avec perte", de: "Verlustbehaftet", pt: "Com perdas", it: "Con perdita",
            nl: "Lossy", ru: "С потерями", pl: "Stratny", tr: "Kayıplı", sv: "Förstörande", nb: "Tapsbasert",
            da: "Tabsbehæftet", fi: "Häviöllinen", zh: "有损", ja: "非可逆", ko: "손실"
        ),
        .album_more_by: tr(
            en: "More by %@", es: "Más de %@", fr: "Plus de %@", de: "Mehr von %@", pt: "Mais de %@", it: "Altro di %@",
            nl: "Meer van %@", ru: "Ещё от %@", pl: "Więcej od %@", tr: "%@ sanatçısından daha fazlası", sv: "Mer av %@", nb: "Mer av %@",
            da: "Mere af %@", fi: "Lisää: %@", zh: "更多%@的作品", ja: "%@の他の作品", ko: "%@의 다른 음악"
        ),
        .album_quality_lossy_title: tr(
            en: "Lossy Album", es: "Álbum con pérdida", fr: "Album avec perte", de: "Verlustbehaftetes Album", pt: "Álbum com perdas", it: "Album con perdita",
            nl: "Lossy album", ru: "Альбом с потерями", pl: "Album stratny", tr: "Kayıplı albüm", sv: "Förstörande album", nb: "Tapsbasert album",
            da: "Tabsbehæftet album", fi: "Häviöllinen albumi", zh: "有损专辑", ja: "非可逆アルバム", ko: "손실 앨범"
        ),
        .album_quality_hires_title: tr(
            en: "Hi-Res Lossless Album", es: "Álbum Hi-Res sin pérdida", fr: "Album Hi-Res Lossless", de: "Hi-Res-Lossless-Album", pt: "Álbum Hi-Res sem perdas", it: "Album Hi-Res Lossless",
            nl: "Hi-Res Lossless-album", ru: "Альбом Hi-Res без потерь", pl: "Album Hi-Res bezstratny", tr: "Hi-Res kayıpsız albüm", sv: "Hi-Res förlustfritt album", nb: "Hi-Res tapsfritt album",
            da: "Hi-Res tabsfrit album", fi: "Hi-Res häviötön albumi", zh: "高解析度无损专辑", ja: "ハイレゾロスレスアルバム", ko: "고해상도 무손실 앨범"
        ),
        .album_quality_lossless_title: tr(
            en: "Lossless Album", es: "Álbum sin pérdida", fr: "Album Lossless", de: "Verlustfreies Album", pt: "Álbum sem perdas", it: "Album Lossless",
            nl: "Lossless-album", ru: "Альбом без потерь", pl: "Album bezstratny", tr: "Kayıpsız albüm", sv: "Förlustfritt album", nb: "Tapsfritt album",
            da: "Tabsfrit album", fi: "Häviötön albumi", zh: "无损专辑", ja: "ロスレスアルバム", ko: "무손실 앨범"
        ),
        .album_quality_mixed_title: tr(
            en: "Mixed Quality Album", es: "Álbum de calidad mixta", fr: "Album de qualité mixte", de: "Album mit gemischter Qualität", pt: "Álbum de qualidade mista", it: "Album a qualità mista",
            nl: "Album met gemengde kwaliteit", ru: "Альбом смешанного качества", pl: "Album o mieszanej jakości", tr: "Karışık kaliteli albüm", sv: "Album med blandad kvalitet", nb: "Album med blandet kvalitet",
            da: "Album med blandet kvalitet", fi: "Sekalaatuinen albumi", zh: "混合音质专辑", ja: "音質混在アルバム", ko: "혼합 품질 앨범"
        ),
        .album_quality_lossy_desc: tr(
            en: "All %d tracks use a lossy format.", es: "Las %d pistas usan un formato con pérdida.", fr: "Les %d titres utilisent un format avec perte.", de: "Alle %d Titel verwenden ein verlustbehaftetes Format.", pt: "As %d faixas usam um formato com perdas.", it: "Tutti i %d brani usano un formato con perdita.",
            nl: "Alle %d nummers gebruiken een lossy formaat.", ru: "Все %d треков используют формат с потерями.", pl: "Wszystkie %d utwory używają formatu stratnego.", tr: "%d parçanın tümü kayıplı format kullanıyor.", sv: "Alla %d spår använder ett förstörande format.", nb: "Alle %d spor bruker et tapsbasert format.",
            da: "Alle %d numre bruger et tabsbehæftet format.", fi: "Kaikki %d kappaletta käyttävät häviöllistä muotoa.", zh: "全部 %d 首曲目使用有损格式。", ja: "%d 曲すべてが非可逆フォーマットです。", ko: "%d개 트랙 모두 손실 형식을 사용합니다."
        ),
        .album_quality_hires_desc: tr(
            en: "All %d tracks are hi-res lossless.", es: "Las %d pistas son Hi-Res sin pérdida.", fr: "Les %d titres sont en Hi-Res Lossless.", de: "Alle %d Titel sind Hi-Res Lossless.", pt: "As %d faixas são Hi-Res sem perdas.", it: "Tutti i %d brani sono Hi-Res Lossless.",
            nl: "Alle %d nummers zijn Hi-Res Lossless.", ru: "Все %d треков — Hi-Res без потерь.", pl: "Wszystkie %d utwory są Hi-Res bezstratne.", tr: "%d parçanın tümü Hi-Res kayıpsız.", sv: "Alla %d spår är Hi-Res förlustfria.", nb: "Alle %d spor er Hi-Res tapsfrie.",
            da: "Alle %d numre er Hi-Res tabsfrie.", fi: "Kaikki %d kappaletta ovat Hi-Res häviöttömiä.", zh: "全部 %d 首曲目为高解析度无损。", ja: "%d 曲すべてがハイレゾロスレスです。", ko: "%d개 트랙 모두 고해상도 무손실입니다."
        ),
        .album_quality_lossless_desc: tr(
            en: "All %d tracks are lossless.", es: "Las %d pistas son sin pérdida.", fr: "Les %d titres sont en Lossless.", de: "Alle %d Titel sind verlustfrei.", pt: "As %d faixas são sem perdas.", it: "Tutti i %d brani sono Lossless.",
            nl: "Alle %d nummers zijn lossless.", ru: "Все %d треков без потерь.", pl: "Wszystkie %d utwory są bezstratne.", tr: "%d parçanın tümü kayıpsız.", sv: "Alla %d spår är förlustfria.", nb: "Alle %d spor er tapsfrie.",
            da: "Alle %d numre er tabsfrie.", fi: "Kaikki %d kappaletta ovat häviöttömiä.", zh: "全部 %d 首曲目为无损。", ja: "%d 曲すべてがロスレスです。", ko: "%d개 트랙 모두 무손실입니다."
        ),
        .album_quality_mixed_desc: tr(
            en: "%d of %d tracks are lossless; the rest use a lossy format.", es: "%d de %d pistas son sin pérdida; el resto usa un formato con pérdida.", fr: "%d titres sur %d sont en Lossless ; les autres utilisent un format avec perte.", de: "%d von %d Titeln sind verlustfrei; der Rest ist verlustbehaftet.", pt: "%d de %d faixas são sem perdas; as restantes usam um formato com perdas.", it: "%d brani su %d sono Lossless; gli altri usano un formato con perdita.",
            nl: "%d van %d nummers zijn lossless; de rest gebruikt een lossy formaat.", ru: "%d из %d треков без потерь; остальные с потерями.", pl: "%d z %d utworów jest bezstratnych; reszta używa formatu stratnego.", tr: "%d/%d parça kayıpsız; gerisi kayıplı format kullanıyor.", sv: "%d av %d spår är förlustfria; resten använder ett förstörande format.", nb: "%d av %d spor er tapsfrie; resten bruker et tapsbasert format.",
            da: "%d af %d numre er tabsfrie; resten bruger et tabsbehæftet format.", fi: "%d/%d kappaletta on häviöttömiä; loput käyttävät häviöllistä muotoa.", zh: "%d/%d 首曲目为无损，其余为有损格式。", ja: "%d/%d 曲がロスレスで、残りは非可逆フォーマットです。", ko: "%d/%d 트랙이 무손실이며 나머지는 손실 형식을 사용합니다."
        ),
        .detail_formats: tr(
            en: "Formats", es: "Formatos", fr: "Formats", de: "Formate", pt: "Formatos", it: "Formati",
            nl: "Formaten", ru: "Форматы", pl: "Formaty", tr: "Formatlar", sv: "Format", nb: "Formater",
            da: "Formater", fi: "Muodot", zh: "格式", ja: "フォーマット", ko: "형식"
        ),
        .detail_sample_rates: tr(
            en: "Sample Rates", es: "Frecuencias de muestreo", fr: "Fréquences d'échantillonnage", de: "Abtastraten", pt: "Taxas de amostragem", it: "Frequenze di campionamento",
            nl: "Samplefrequenties", ru: "Частоты дискретизации", pl: "Częstotliwości próbkowania", tr: "Örnekleme hızları", sv: "Samplingsfrekvenser", nb: "Samplingsfrekvenser",
            da: "Samplingsfrekvenser", fi: "Näytteenottotaajuudet", zh: "采样率", ja: "サンプルレート", ko: "샘플링 레이트"
        ),
        .detail_bit_depths: tr(
            en: "Bit Depths", es: "Profundidades de bits", fr: "Profondeurs de bits", de: "Bittiefen", pt: "Profundidades de bits", it: "Profondità di bit",
            nl: "Bitdiepten", ru: "Битность", pl: "Głębie bitowe", tr: "Bit derinlikleri", sv: "Bitdjup", nb: "Bitdybder",
            da: "Bitdybder", fi: "Bittisyvyydet", zh: "位深", ja: "ビット深度", ko: "비트 심도"
        ),
        .detail_hires_tracks: tr(
            en: "Hi-Res Tracks", es: "Pistas Hi-Res", fr: "Titres Hi-Res", de: "Hi-Res-Titel", pt: "Faixas Hi-Res", it: "Brani Hi-Res",
            nl: "Hi-Res-nummers", ru: "Треки Hi-Res", pl: "Utwory Hi-Res", tr: "Hi-Res parçalar", sv: "Hi-Res-spår", nb: "Hi-Res-spor",
            da: "Hi-Res-numre", fi: "Hi-Res-kappaleet", zh: "高解析度曲目", ja: "ハイレゾ曲", ko: "고해상도 트랙"
        ),
        .detail_x_of_y: tr(
            en: "%d of %d", es: "%d de %d", fr: "%d sur %d", de: "%d von %d", pt: "%d de %d", it: "%d di %d",
            nl: "%d van %d", ru: "%d из %d", pl: "%d z %d", tr: "%d / %d", sv: "%d av %d", nb: "%d av %d",
            da: "%d af %d", fi: "%d/%d", zh: "%d / %d", ja: "%d / %d", ko: "%d / %d"
        ),
        .detail_bit_value: tr(
            en: "%d-bit", es: "%d bits", fr: "%d bits", de: "%d Bit", pt: "%d bits", it: "%d bit",
            nl: "%d-bit", ru: "%d бит", pl: "%d-bit", tr: "%d bit", sv: "%d-bitars", nb: "%d-bit",
            da: "%d-bit", fi: "%d-bittinen", zh: "%d 位", ja: "%d ビット", ko: "%d비트"
        ),

        // MARK: Queue
        .queue_repeat: tr(
            en: "Repeat", es: "Repetir", fr: "Répéter", de: "Wiederholen", pt: "Repetir", it: "Ripeti",
            nl: "Herhalen", ru: "Повтор", pl: "Powtarzaj", tr: "Tekrarla", sv: "Upprepa", nb: "Gjenta",
            da: "Gentag", fi: "Toista", zh: "重复", ja: "リピート", ko: "반복"
        ),
        .queue_repeat_one: tr(
            en: "Repeat 1", es: "Repetir 1", fr: "Répéter 1", de: "1 wiederholen", pt: "Repetir 1", it: "Ripeti 1",
            nl: "1 herhalen", ru: "Повтор 1", pl: "Powtórz 1", tr: "1 tekrarla", sv: "Upprepa 1", nb: "Gjenta 1",
            da: "Gentag 1", fi: "Toista 1", zh: "单曲重复", ja: "1曲リピート", ko: "한 곡 반복"
        ),

        // MARK: Library
        .library_search_prompt: tr(
            en: "Search Library", es: "Buscar en biblioteca", fr: "Rechercher dans la bibliothèque", de: "Mediathek durchsuchen", pt: "Pesquisar na biblioteca", it: "Cerca nella libreria",
            nl: "Zoek in bibliotheek", ru: "Поиск в медиатеке", pl: "Szukaj w bibliotece", tr: "Kitaplıkta ara", sv: "Sök i biblioteket", nb: "Søk i biblioteket",
            da: "Søg i biblioteket", fi: "Hae kirjastosta", zh: "搜索音乐库", ja: "ライブラリを検索", ko: "라이브러리 검색"
        ),
        .library_folders: tr(
            en: "Folders", es: "Carpetas", fr: "Dossiers", de: "Ordner", pt: "Pastas", it: "Cartelle",
            nl: "Mappen", ru: "Папки", pl: "Foldery", tr: "Klasörler", sv: "Mappar", nb: "Mapper",
            da: "Mapper", fi: "Kansiot", zh: "文件夹", ja: "フォルダ", ko: "폴더"
        ),
        .library_source: tr(
            en: "Source", es: "Origen", fr: "Source", de: "Quelle", pt: "Origem", it: "Origine",
            nl: "Bron", ru: "Источник", pl: "Źródło", tr: "Kaynak", sv: "Källa", nb: "Kilde",
            da: "Kilde", fi: "Lähde", zh: "来源", ja: "ソース", ko: "소스"
        ),
        .library_sort_by: tr(
            en: "Sort By", es: "Ordenar por", fr: "Trier par", de: "Sortieren nach", pt: "Ordenar por", it: "Ordina per",
            nl: "Sorteren op", ru: "Сортировать по", pl: "Sortuj wg", tr: "Sırala", sv: "Sortera efter", nb: "Sorter etter",
            da: "Sortér efter", fi: "Lajittele", zh: "排序方式", ja: "並べ替え", ko: "정렬 기준"
        ),
        .library_all_genres: tr(
            en: "All Genres", es: "Todos los géneros", fr: "Tous les genres", de: "Alle Genres", pt: "Todos os géneros", it: "Tutti i generi",
            nl: "Alle genres", ru: "Все жанры", pl: "Wszystkie gatunki", tr: "Tüm türler", sv: "Alla genrer", nb: "Alle sjangere",
            da: "Alle genrer", fi: "Kaikki genret", zh: "所有流派", ja: "すべてのジャンル", ko: "모든 장르"
        ),
        .library_never_played: tr(
            en: "Never Played", es: "Nunca reproducido", fr: "Jamais lu", de: "Nie gespielt", pt: "Nunca reproduzido", it: "Mai riprodotto",
            nl: "Nooit afgespeeld", ru: "Не воспроизводилось", pl: "Nigdy nieodtwarzane", tr: "Hiç çalınmadı", sv: "Aldrig spelad", nb: "Aldri spilt",
            da: "Aldrig afspillet", fi: "Ei koskaan toistettu", zh: "从未播放", ja: "未再生", ko: "재생 안 함"
        ),
        .library_clear_filters: tr(
            en: "Clear Filters", es: "Borrar filtros", fr: "Effacer les filtres", de: "Filter löschen", pt: "Limpar filtros", it: "Cancella filtri",
            nl: "Filters wissen", ru: "Сбросить фильтры", pl: "Wyczyść filtry", tr: "Filtreleri temizle", sv: "Rensa filter", nb: "Tøm filtre",
            da: "Ryd filtre", fi: "Tyhjennä suodattimet", zh: "清除筛选", ja: "フィルタをクリア", ko: "필터 지우기"
        ),
        .library_all_folders: tr(
            en: "All Folders", es: "Todas las carpetas", fr: "Tous les dossiers", de: "Alle Ordner", pt: "Todas as pastas", it: "Tutte le cartelle",
            nl: "Alle mappen", ru: "Все папки", pl: "Wszystkie foldery", tr: "Tüm klasörler", sv: "Alla mappar", nb: "Alle mapper",
            da: "Alle mapper", fi: "Kaikki kansiot", zh: "所有文件夹", ja: "すべてのフォルダ", ko: "모든 폴더"
        ),
        .library_select_all: tr(
            en: "Select All", es: "Seleccionar todo", fr: "Tout sélectionner", de: "Alle auswählen", pt: "Selecionar tudo", it: "Seleziona tutto",
            nl: "Alles selecteren", ru: "Выбрать все", pl: "Zaznacz wszystko", tr: "Tümünü seç", sv: "Markera alla", nb: "Velg alle",
            da: "Vælg alle", fi: "Valitse kaikki", zh: "全选", ja: "すべて選択", ko: "모두 선택"
        ),
        .library_deselect_all: tr(
            en: "Deselect All", es: "Deseleccionar todo", fr: "Tout désélectionner", de: "Auswahl aufheben", pt: "Desmarcar tudo", it: "Deseleziona tutto",
            nl: "Alles deselecteren", ru: "Снять выбор", pl: "Odznacz wszystko", tr: "Seçimi kaldır", sv: "Avmarkera alla", nb: "Fjern alle",
            da: "Fravælg alle", fi: "Poista valinnat", zh: "取消全选", ja: "すべて選択解除", ko: "모두 선택 해제"
        ),
        .library_add_n_songs: tr(
            en: "Add %d Songs", es: "Añadir %d canciones", fr: "Ajouter %d titres", de: "%d Songs hinzufügen", pt: "Adicionar %d músicas", it: "Aggiungi %d brani",
            nl: "%d nummers toevoegen", ru: "Добавить %d песен", pl: "Dodaj %d utworów", tr: "%d şarkı ekle", sv: "Lägg till %d låtar", nb: "Legg til %d låter",
            da: "Tilføj %d sange", fi: "Lisää %d kappaletta", zh: "添加 %d 首歌曲", ja: "%d 曲を追加", ko: "%d곡 추가"
        ),
        .action_queue: tr(
            en: "Queue", es: "Cola", fr: "File d'attente", de: "Warteschlange", pt: "Fila", it: "Coda",
            nl: "Wachtrij", ru: "Очередь", pl: "Kolejka", tr: "Sıra", sv: "Kö", nb: "Kø",
            da: "Kø", fi: "Jono", zh: "队列", ja: "キュー", ko: "대기열"
        ),
        .media_playlist: tr(
            en: "Playlist", es: "Lista", fr: "Playlist", de: "Playlist", pt: "Lista", it: "Playlist",
            nl: "Afspeellijst", ru: "Плейлист", pl: "Playlista", tr: "Çalma listesi", sv: "Spellista", nb: "Spilleliste",
            da: "Playliste", fi: "Soittolista", zh: "播放列表", ja: "プレイリスト", ko: "재생목록"
        ),
        .library_source_server: tr(
            en: "Server", es: "Servidor", fr: "Serveur", de: "Server", pt: "Servidor", it: "Server",
            nl: "Server", ru: "Сервер", pl: "Serwer", tr: "Sunucu", sv: "Server", nb: "Server",
            da: "Server", fi: "Palvelin", zh: "服务器", ja: "サーバ", ko: "서버"
        ),
        .library_source_downloaded: tr(
            en: "Downloaded", es: "Descargado", fr: "Téléchargé", de: "Heruntergeladen", pt: "Baixado", it: "Scaricato",
            nl: "Gedownload", ru: "Загружено", pl: "Pobrane", tr: "İndirildi", sv: "Nedladdat", nb: "Lastet ned",
            da: "Downloadet", fi: "Ladattu", zh: "已下载", ja: "ダウンロード済み", ko: "다운로드됨"
        ),
        .sort_name: tr(
            en: "Name", es: "Nombre", fr: "Nom", de: "Name", pt: "Nome", it: "Nome",
            nl: "Naam", ru: "Имя", pl: "Nazwa", tr: "Ad", sv: "Namn", nb: "Navn",
            da: "Navn", fi: "Nimi", zh: "名称", ja: "名前", ko: "이름"
        ),
        .sort_most_played: tr(
            en: "Most Played", es: "Más reproducido", fr: "Les plus écoutés", de: "Meistgespielt", pt: "Mais reproduzido", it: "Più riprodotti",
            nl: "Meest afgespeeld", ru: "Часто играемые", pl: "Najczęściej odtwarzane", tr: "En çok çalınan", sv: "Mest spelade", nb: "Mest spilt",
            da: "Mest afspillet", fi: "Eniten toistetut", zh: "最常播放", ja: "再生回数順", ko: "많이 재생됨"
        ),
        .playlists_none_yet: tr(
            en: "No playlists yet", es: "Aún no hay listas", fr: "Aucune playlist pour l'instant", de: "Noch keine Playlists", pt: "Ainda sem listas", it: "Ancora nessuna playlist",
            nl: "Nog geen afspeellijsten", ru: "Пока нет плейлистов", pl: "Brak playlist", tr: "Henüz çalma listesi yok", sv: "Inga spellistor än", nb: "Ingen spillelister ennå",
            da: "Ingen playlister endnu", fi: "Ei vielä soittolistoja", zh: "还没有播放列表", ja: "プレイリストはまだありません", ko: "아직 재생목록이 없습니다"
        ),
        .toast_added_count_to: tr(
            en: "Added %d to %@", es: "Se añadieron %d a %@", fr: "%d ajoutés à %@", de: "%d zu %@ hinzugefügt", pt: "%d adicionados a %@", it: "%d aggiunti a %@",
            nl: "%d toegevoegd aan %@", ru: "Добавлено %d в %@", pl: "Dodano %d do %@", tr: "%d öğe %@ listesine eklendi", sv: "%d tillagda i %@", nb: "%d lagt til i %@",
            da: "%d føjet til %@", fi: "Lisätty %d kohteeseen %@", zh: "已将 %d 首添加到%@", ja: "%d 曲を%@に追加しました", ko: "%d개를 %@에 추가함"
        ),
        .toast_playing_n_next: tr(
            en: "Playing %d next", es: "Reproduciendo %d a continuación", fr: "%d à suivre", de: "%d als Nächstes", pt: "A reproduzir %d a seguir", it: "%d in riproduzione successiva",
            nl: "%d hierna afspelen", ru: "%d в очереди далее", pl: "Następnie %d", tr: "Sıradaki %d", sv: "Spelar %d härnäst", nb: "Spiller %d neste",
            da: "Afspiller %d næst", fi: "Toistetaan %d seuraavaksi", zh: "接下来播放 %d 首", ja: "次に %d 曲を再生", ko: "다음에 %d개 재생"
        ),
        .toast_added_n_to_queue: tr(
            en: "Added %d to queue", es: "%d añadidos a la cola", fr: "%d ajoutés à la file", de: "%d zur Warteschlange hinzugefügt", pt: "%d adicionados à fila", it: "%d aggiunti alla coda",
            nl: "%d toegevoegd aan wachtrij", ru: "%d добавлено в очередь", pl: "Dodano %d do kolejki", tr: "%d öğe sıraya eklendi", sv: "%d tillagda i kön", nb: "%d lagt til i køen",
            da: "%d føjet til køen", fi: "Lisätty %d jonoon", zh: "已将 %d 首添加到队列", ja: "%d 曲をキューに追加", ko: "%d개를 대기열에 추가함"
        ),
        .toast_downloading_n: tr(
            en: "Downloading %d", es: "Descargando %d", fr: "Téléchargement de %d", de: "%d werden geladen", pt: "A baixar %d", it: "Download di %d",
            nl: "%d downloaden", ru: "Загрузка %d", pl: "Pobieranie %d", tr: "%d indiriliyor", sv: "Laddar ner %d", nb: "Laster ned %d",
            da: "Downloader %d", fi: "Ladataan %d", zh: "正在下载 %d 首", ja: "%d 曲をダウンロード中", ko: "%d개 다운로드 중"
        ),

        // MARK: Playlists screen
        .playlists_search_prompt: tr(
            en: "Search playlists", es: "Buscar listas", fr: "Rechercher des playlists", de: "Playlists durchsuchen", pt: "Pesquisar listas", it: "Cerca playlist",
            nl: "Zoek afspeellijsten", ru: "Поиск плейлистов", pl: "Szukaj playlist", tr: "Çalma listelerinde ara", sv: "Sök spellistor", nb: "Søk i spillelister",
            da: "Søg i playlister", fi: "Hae soittolistoja", zh: "搜索播放列表", ja: "プレイリストを検索", ko: "재생목록 검색"
        ),
        .playlists_count: tr(
            en: "%d playlists", es: "%d listas", fr: "%d playlists", de: "%d Playlists", pt: "%d listas", it: "%d playlist",
            nl: "%d afspeellijsten", ru: "%d плейлистов", pl: "%d playlist", tr: "%d çalma listesi", sv: "%d spellistor", nb: "%d spillelister",
            da: "%d playlister", fi: "%d soittolistaa", zh: "%d 个播放列表", ja: "%d 個のプレイリスト", ko: "재생목록 %d개"
        ),
        .playlist_delete_q: tr(
            en: "Delete Playlist?", es: "¿Eliminar lista?", fr: "Supprimer la playlist ?", de: "Playlist löschen?", pt: "Eliminar lista?", it: "Eliminare la playlist?",
            nl: "Afspeellijst verwijderen?", ru: "Удалить плейлист?", pl: "Usunąć playlistę?", tr: "Çalma listesi silinsin mi?", sv: "Radera spellista?", nb: "Slette spilleliste?",
            da: "Slet playliste?", fi: "Poistetaanko soittolista?", zh: "删除播放列表？", ja: "プレイリストを削除しますか？", ko: "재생목록을 삭제할까요?"
        ),
        .playlist_delete_named: tr(
            en: "Delete “%@”", es: "Eliminar «%@»", fr: "Supprimer « %@ »", de: "„%@“ löschen", pt: "Eliminar “%@”", it: "Elimina “%@”",
            nl: "“%@” verwijderen", ru: "Удалить «%@»", pl: "Usuń „%@”", tr: "“%@” sil", sv: "Radera ”%@”", nb: "Slett «%@»",
            da: "Slet “%@”", fi: "Poista ”%@”", zh: "删除“%@”", ja: "「%@」を削除", ko: "“%@” 삭제"
        ),
        .playlist_delete_msg: tr(
            en: "“%@” will be permanently deleted. This can’t be undone.", es: "«%@» se eliminará permanentemente. No se puede deshacer.", fr: "« %@ » sera définitivement supprimée. Action irréversible.", de: "„%@“ wird endgültig gelöscht. Das kann nicht rückgängig gemacht werden.", pt: "“%@” será eliminada permanentemente. Não pode ser desfeito.", it: "“%@” verrà eliminata definitivamente. L’operazione è irreversibile.",
            nl: "“%@” wordt permanent verwijderd. Dit kan niet ongedaan worden gemaakt.", ru: "«%@» будет удалён безвозвратно. Это действие нельзя отменить.", pl: "„%@” zostanie trwale usunięta. Nie można tego cofnąć.", tr: "“%@” kalıcı olarak silinecek. Bu geri alınamaz.", sv: "”%@” raderas permanent. Detta kan inte ångras.", nb: "«%@» slettes permanent. Dette kan ikke angres.",
            da: "“%@” slettes permanent. Dette kan ikke fortrydes.", fi: "”%@” poistetaan pysyvästi. Tätä ei voi kumota.", zh: "“%@”将被永久删除，此操作无法撤销。", ja: "「%@」は完全に削除されます。元に戻せません。", ko: "“%@”이(가) 영구적으로 삭제됩니다. 되돌릴 수 없습니다."
        ),
        .smart_delete_q: tr(
            en: "Delete Smart Playlist?", es: "¿Eliminar lista inteligente?", fr: "Supprimer la playlist intelligente ?", de: "Intelligente Playlist löschen?", pt: "Eliminar lista inteligente?", it: "Eliminare la playlist smart?",
            nl: "Slimme afspeellijst verwijderen?", ru: "Удалить умный плейлист?", pl: "Usunąć inteligentną playlistę?", tr: "Akıllı çalma listesi silinsin mi?", sv: "Radera smart spellista?", nb: "Slette smart spilleliste?",
            da: "Slet smart playliste?", fi: "Poistetaanko älykäs soittolista?", zh: "删除智能播放列表？", ja: "スマートプレイリストを削除しますか？", ko: "스마트 재생목록을 삭제할까요?"
        ),
        .smart_delete_msg: tr(
            en: "“%@” will be removed from this device.", es: "«%@» se eliminará de este dispositivo.", fr: "« %@ » sera supprimée de cet appareil.", de: "„%@“ wird von diesem Gerät entfernt.", pt: "“%@” será removida deste dispositivo.", it: "“%@” verrà rimossa da questo dispositivo.",
            nl: "“%@” wordt van dit apparaat verwijderd.", ru: "«%@» будет удалён с этого устройства.", pl: "„%@” zostanie usunięta z tego urządzenia.", tr: "“%@” bu cihazdan kaldırılacak.", sv: "”%@” tas bort från den här enheten.", nb: "«%@» fjernes fra denne enheten.",
            da: "“%@” fjernes fra denne enhed.", fi: "”%@” poistetaan tästä laitteesta.", zh: "“%@”将从此设备中移除。", ja: "「%@」はこのデバイスから削除されます。", ko: "“%@”이(가) 이 기기에서 제거됩니다."
        ),
        .folder_delete_q: tr(
            en: "Delete Folder?", es: "¿Eliminar carpeta?", fr: "Supprimer le dossier ?", de: "Ordner löschen?", pt: "Eliminar pasta?", it: "Eliminare la cartella?",
            nl: "Map verwijderen?", ru: "Удалить папку?", pl: "Usunąć folder?", tr: "Klasör silinsin mi?", sv: "Radera mapp?", nb: "Slette mappe?",
            da: "Slet mappe?", fi: "Poistetaanko kansio?", zh: "删除文件夹？", ja: "フォルダを削除しますか？", ko: "폴더를 삭제할까요?"
        ),
        .folder_delete_msg: tr(
            en: "“%@” will be removed. Playlists inside it will stay intact.", es: "«%@» se eliminará. Las listas que contiene se conservarán.", fr: "« %@ » sera supprimé. Les playlists qu’il contient seront conservées.", de: "„%@“ wird entfernt. Die enthaltenen Playlists bleiben erhalten.", pt: "“%@” será removida. As listas no seu interior permanecerão intactas.", it: "“%@” verrà rimossa. Le playlist al suo interno resteranno intatte.",
            nl: "“%@” wordt verwijderd. De afspeellijsten erin blijven behouden.", ru: "«%@» будет удалена. Плейлисты внутри останутся.", pl: "„%@” zostanie usunięty. Playlisty w środku pozostaną nienaruszone.", tr: "“%@” kaldırılacak. İçindeki çalma listeleri korunacak.", sv: "”%@” tas bort. Spellistorna i den behålls.", nb: "«%@» fjernes. Spillelistene i den beholdes.",
            da: "“%@” fjernes. Playlisterne i den bevares.", fi: "”%@” poistetaan. Sen sisällä olevat soittolistat säilyvät.", zh: "“%@”将被移除，其中的播放列表会保留。", ja: "「%@」は削除されます。中のプレイリストは保持されます。", ko: "“%@”이(가) 제거됩니다. 안의 재생목록은 유지됩니다."
        ),
        .playlist_pin: tr(
            en: "Pin to Top", es: "Fijar arriba", fr: "Épingler en haut", de: "Oben anheften", pt: "Fixar no topo", it: "Fissa in alto",
            nl: "Bovenaan vastzetten", ru: "Закрепить вверху", pl: "Przypnij na górze", tr: "Üste sabitle", sv: "Fäst överst", nb: "Fest øverst",
            da: "Fastgør øverst", fi: "Kiinnitä ylös", zh: "置顶", ja: "上部に固定", ko: "맨 위에 고정"
        ),
        .playlist_unpin: tr(
            en: "Unpin", es: "Dejar de fijar", fr: "Détacher", de: "Lösen", pt: "Desafixar", it: "Rimuovi",
            nl: "Losmaken", ru: "Открепить", pl: "Odepnij", tr: "Sabitlemeyi kaldır", sv: "Lossa", nb: "Løsne",
            da: "Frigør", fi: "Poista kiinnitys", zh: "取消置顶", ja: "固定を解除", ko: "고정 해제"
        ),
        .folder_add_to: tr(
            en: "Add to Folder", es: "Añadir a carpeta", fr: "Ajouter au dossier", de: "Zu Ordner hinzufügen", pt: "Adicionar à pasta", it: "Aggiungi a cartella",
            nl: "Aan map toevoegen", ru: "Добавить в папку", pl: "Dodaj do folderu", tr: "Klasöre ekle", sv: "Lägg till i mapp", nb: "Legg til i mappe",
            da: "Føj til mappe", fi: "Lisää kansioon", zh: "添加到文件夹", ja: "フォルダに追加", ko: "폴더에 추가"
        ),
        .folder_remove_from: tr(
            en: "Remove from Folder", es: "Quitar de la carpeta", fr: "Retirer du dossier", de: "Aus Ordner entfernen", pt: "Remover da pasta", it: "Rimuovi dalla cartella",
            nl: "Uit map verwijderen", ru: "Убрать из папки", pl: "Usuń z folderu", tr: "Klasörden çıkar", sv: "Ta bort från mapp", nb: "Fjern fra mappe",
            da: "Fjern fra mappe", fi: "Poista kansiosta", zh: "从文件夹移除", ja: "フォルダから削除", ko: "폴더에서 제거"
        ),
        .media_folder: tr(
            en: "Folder", es: "Carpeta", fr: "Dossier", de: "Ordner", pt: "Pasta", it: "Cartella",
            nl: "Map", ru: "Папка", pl: "Folder", tr: "Klasör", sv: "Mapp", nb: "Mappe",
            da: "Mappe", fi: "Kansio", zh: "文件夹", ja: "フォルダ", ko: "폴더"
        ),
        .folder_empty: tr(
            en: "Empty Folder", es: "Carpeta vacía", fr: "Dossier vide", de: "Leerer Ordner", pt: "Pasta vazia", it: "Cartella vuota",
            nl: "Lege map", ru: "Пустая папка", pl: "Pusty folder", tr: "Boş klasör", sv: "Tom mapp", nb: "Tom mappe",
            da: "Tom mappe", fi: "Tyhjä kansio", zh: "空文件夹", ja: "空のフォルダ", ko: "빈 폴더"
        ),
        .action_clear_selection: tr(
            en: "Clear Selection", es: "Borrar selección", fr: "Effacer la sélection", de: "Auswahl aufheben", pt: "Limpar seleção", it: "Cancella selezione",
            nl: "Selectie wissen", ru: "Снять выделение", pl: "Wyczyść zaznaczenie", tr: "Seçimi temizle", sv: "Rensa markering", nb: "Tøm utvalg",
            da: "Ryd markering", fi: "Tyhjennä valinta", zh: "清除选择", ja: "選択を解除", ko: "선택 해제"
        ),
        .search_x: tr(
            en: "Search %@", es: "Buscar %@", fr: "Rechercher %@", de: "%@ durchsuchen", pt: "Pesquisar %@", it: "Cerca %@",
            nl: "Zoek %@", ru: "Поиск: %@", pl: "Szukaj %@", tr: "%@ ara", sv: "Sök %@", nb: "Søk %@",
            da: "Søg %@", fi: "Hae %@", zh: "搜索%@", ja: "%@を検索", ko: "%@ 검색"
        ),
        .create_type: tr(
            en: "Type", es: "Tipo", fr: "Type", de: "Typ", pt: "Tipo", it: "Tipo",
            nl: "Type", ru: "Тип", pl: "Typ", tr: "Tür", sv: "Typ", nb: "Type",
            da: "Type", fi: "Tyyppi", zh: "类型", ja: "種類", ko: "유형"
        ),
        .create_playlist_name_ph: tr(
            en: "Playlist name", es: "Nombre de la lista", fr: "Nom de la playlist", de: "Playlist-Name", pt: "Nome da lista", it: "Nome della playlist",
            nl: "Naam afspeellijst", ru: "Название плейлиста", pl: "Nazwa playlisty", tr: "Çalma listesi adı", sv: "Spellistans namn", nb: "Navn på spilleliste",
            da: "Playlistens navn", fi: "Soittolistan nimi", zh: "播放列表名称", ja: "プレイリスト名", ko: "재생목록 이름"
        ),
        .create_folder_name_ph: tr(
            en: "Folder name", es: "Nombre de la carpeta", fr: "Nom du dossier", de: "Ordnername", pt: "Nome da pasta", it: "Nome della cartella",
            nl: "Mapnaam", ru: "Название папки", pl: "Nazwa folderu", tr: "Klasör adı", sv: "Mappnamn", nb: "Mappenavn",
            da: "Mappenavn", fi: "Kansion nimi", zh: "文件夹名称", ja: "フォルダ名", ko: "폴더 이름"
        ),
        .create_new_playlist_title: tr(
            en: "New Playlist", es: "Nueva lista", fr: "Nouvelle playlist", de: "Neue Playlist", pt: "Nova lista", it: "Nuova playlist",
            nl: "Nieuwe afspeellijst", ru: "Новый плейлист", pl: "Nowa playlista", tr: "Yeni çalma listesi", sv: "Ny spellista", nb: "Ny spilleliste",
            da: "Ny playliste", fi: "Uusi soittolista", zh: "新建播放列表", ja: "新規プレイリスト", ko: "새 재생목록"
        ),
        .action_create: tr(
            en: "Create", es: "Crear", fr: "Créer", de: "Erstellen", pt: "Criar", it: "Crea",
            nl: "Aanmaken", ru: "Создать", pl: "Utwórz", tr: "Oluştur", sv: "Skapa", nb: "Opprett",
            da: "Opret", fi: "Luo", zh: "创建", ja: "作成", ko: "만들기"
        ),
        .name_exists_title: tr(
            en: "Name Already Exists", es: "El nombre ya existe", fr: "Ce nom existe déjà", de: "Name existiert bereits", pt: "O nome já existe", it: "Il nome esiste già",
            nl: "Naam bestaat al", ru: "Имя уже существует", pl: "Nazwa już istnieje", tr: "Ad zaten var", sv: "Namnet finns redan", nb: "Navnet finnes allerede",
            da: "Navnet findes allerede", fi: "Nimi on jo olemassa", zh: "名称已存在", ja: "名前は既に存在します", ko: "이미 존재하는 이름"
        ),
        .smart_songs_rule: tr(
            en: "%d songs · %@", es: "%d canciones · %@", fr: "%d titres · %@", de: "%d Songs · %@", pt: "%d músicas · %@", it: "%d brani · %@",
            nl: "%d nummers · %@", ru: "%d песен · %@", pl: "%d utworów · %@", tr: "%d şarkı · %@", sv: "%d låtar · %@", nb: "%d låter · %@",
            da: "%d sange · %@", fi: "%d kappaletta · %@", zh: "%d 首歌曲 · %@", ja: "%d 曲 · %@", ko: "%d곡 · %@"
        ),

        // MARK: Smart playlist editor
        .smart_name_ph: tr(
            en: "Smart playlist name", es: "Nombre de lista inteligente", fr: "Nom de la playlist intelligente", de: "Name der intelligenten Playlist", pt: "Nome da lista inteligente", it: "Nome playlist smart",
            nl: "Naam slimme afspeellijst", ru: "Название умного плейлиста", pl: "Nazwa inteligentnej playlisty", tr: "Akıllı çalma listesi adı", sv: "Smart spellistas namn", nb: "Navn på smart spilleliste",
            da: "Smart playlistes navn", fi: "Älykkään soittolistan nimi", zh: "智能播放列表名称", ja: "スマートプレイリスト名", ko: "스마트 재생목록 이름"
        ),
        .smart_desc: tr(
            en: "Description", es: "Descripción", fr: "Description", de: "Beschreibung", pt: "Descrição", it: "Descrizione",
            nl: "Beschrijving", ru: "Описание", pl: "Opis", tr: "Açıklama", sv: "Beskrivning", nb: "Beskrivelse",
            da: "Beskrivelse", fi: "Kuvaus", zh: "描述", ja: "説明", ko: "설명"
        ),
        .smart_section_rules: tr(
            en: "Rules", es: "Reglas", fr: "Règles", de: "Regeln", pt: "Regras", it: "Regole",
            nl: "Regels", ru: "Правила", pl: "Reguły", tr: "Kurallar", sv: "Regler", nb: "Regler",
            da: "Regler", fi: "Säännöt", zh: "规则", ja: "ルール", ko: "규칙"
        ),
        .smart_match: tr(
            en: "Match", es: "Coincidencia", fr: "Correspondance", de: "Übereinstimmung", pt: "Correspondência", it: "Corrispondenza",
            nl: "Overeenkomst", ru: "Совпадение", pl: "Dopasowanie", tr: "Eşleşme", sv: "Matchning", nb: "Treff",
            da: "Match", fi: "Vastaavuus", zh: "匹配", ja: "一致", ko: "일치"
        ),
        .smart_search_ph: tr(
            en: "Title, artist, album, genre contains", es: "Título, artista, álbum o género contiene", fr: "Titre, artiste, album, genre contient", de: "Titel, Künstler, Album, Genre enthält", pt: "Título, artista, álbum, género contém", it: "Titolo, artista, album, genere contiene",
            nl: "Titel, artiest, album, genre bevat", ru: "Название, артист, альбом, жанр содержит", pl: "Tytuł, wykonawca, album, gatunek zawiera", tr: "Başlık, sanatçı, albüm, tür içerir", sv: "Titel, artist, album, genre innehåller", nb: "Tittel, artist, album, sjanger inneholder",
            da: "Titel, kunstner, album, genre indeholder", fi: "Nimi, artisti, albumi, genre sisältää", zh: "标题、艺人、专辑、流派包含", ja: "タイトル・アーティスト・アルバム・ジャンルに含む", ko: "제목, 아티스트, 앨범, 장르 포함"
        ),
        .smart_artist_ph: tr(
            en: "Artist contains", es: "El artista contiene", fr: "L’artiste contient", de: "Künstler enthält", pt: "O artista contém", it: "L’artista contiene",
            nl: "Artiest bevat", ru: "Артист содержит", pl: "Wykonawca zawiera", tr: "Sanatçı içerir", sv: "Artist innehåller", nb: "Artist inneholder",
            da: "Kunstner indeholder", fi: "Artisti sisältää", zh: "艺人包含", ja: "アーティストに含む", ko: "아티스트 포함"
        ),
        .smart_album_ph: tr(
            en: "Album contains", es: "El álbum contiene", fr: "L’album contient", de: "Album enthält", pt: "O álbum contém", it: "L’album contiene",
            nl: "Album bevat", ru: "Альбом содержит", pl: "Album zawiera", tr: "Albüm içerir", sv: "Album innehåller", nb: "Album inneholder",
            da: "Album indeholder", fi: "Albumi sisältää", zh: "专辑包含", ja: "アルバムに含む", ko: "앨범 포함"
        ),
        .smart_any_genre: tr(
            en: "Any Genre", es: "Cualquier género", fr: "Tous les genres", de: "Beliebiges Genre", pt: "Qualquer género", it: "Qualsiasi genere",
            nl: "Elk genre", ru: "Любой жанр", pl: "Dowolny gatunek", tr: "Herhangi bir tür", sv: "Valfri genre", nb: "Hvilken som helst sjanger",
            da: "Enhver genre", fi: "Mikä tahansa genre", zh: "任意流派", ja: "すべてのジャンル", ko: "모든 장르"
        ),
        .smart_section_filters: tr(
            en: "Filters", es: "Filtros", fr: "Filtres", de: "Filter", pt: "Filtros", it: "Filtri",
            nl: "Filters", ru: "Фильтры", pl: "Filtry", tr: "Filtreler", sv: "Filter", nb: "Filtre",
            da: "Filtre", fi: "Suodattimet", zh: "筛选", ja: "フィルタ", ko: "필터"
        ),
        .smart_min_year_ph: tr(
            en: "Minimum year", es: "Año mínimo", fr: "Année minimale", de: "Mindestjahr", pt: "Ano mínimo", it: "Anno minimo",
            nl: "Minimumjaar", ru: "Минимальный год", pl: "Rok minimalny", tr: "En küçük yıl", sv: "Minsta år", nb: "Minste år",
            da: "Mindste år", fi: "Vähimmäisvuosi", zh: "最早年份", ja: "最小の年", ko: "최소 연도"
        ),
        .smart_max_year_ph: tr(
            en: "Maximum year", es: "Año máximo", fr: "Année maximale", de: "Höchstjahr", pt: "Ano máximo", it: "Anno massimo",
            nl: "Maximumjaar", ru: "Максимальный год", pl: "Rok maksymalny", tr: "En büyük yıl", sv: "Högsta år", nb: "Største år",
            da: "Største år", fi: "Enimmäisvuosi", zh: "最晚年份", ja: "最大の年", ko: "최대 연도"
        ),
        .smart_min_plays_ph: tr(
            en: "Minimum plays", es: "Reproducciones mínimas", fr: "Lectures minimales", de: "Mindestwiedergaben", pt: "Reproduções mínimas", it: "Riproduzioni minime",
            nl: "Minimum aantal keer afgespeeld", ru: "Минимум прослушиваний", pl: "Minimalna liczba odtworzeń", tr: "En az çalma", sv: "Minsta antal spelningar", nb: "Minste antall avspillinger",
            da: "Mindste antal afspilninger", fi: "Vähimmäistoistot", zh: "最少播放次数", ja: "最小再生回数", ko: "최소 재생 횟수"
        ),
        .smart_max_plays_ph: tr(
            en: "Maximum plays", es: "Reproducciones máximas", fr: "Lectures maximales", de: "Höchstwiedergaben", pt: "Reproduções máximas", it: "Riproduzioni massime",
            nl: "Maximum aantal keer afgespeeld", ru: "Максимум прослушиваний", pl: "Maksymalna liczba odtworzeń", tr: "En çok çalma", sv: "Högsta antal spelningar", nb: "Største antall avspillinger",
            da: "Største antal afspilninger", fi: "Enimmäistoistot", zh: "最多播放次数", ja: "最大再生回数", ko: "최대 재생 횟수"
        ),
        .smart_never_played_only: tr(
            en: "Never Played Only", es: "Solo nunca reproducidas", fr: "Jamais lus uniquement", de: "Nur nie gespielte", pt: "Apenas nunca reproduzidas", it: "Solo mai riprodotti",
            nl: "Alleen nooit afgespeeld", ru: "Только не воспроизводившиеся", pl: "Tylko nigdy nieodtwarzane", tr: "Yalnızca hiç çalınmayanlar", sv: "Endast aldrig spelade", nb: "Bare aldri spilt",
            da: "Kun aldrig afspillede", fi: "Vain ei koskaan toistetut", zh: "仅从未播放", ja: "未再生のみ", ko: "재생 안 한 항목만"
        ),
        .smart_lossless_only: tr(
            en: "Lossless Only", es: "Solo sin pérdida", fr: "Lossless uniquement", de: "Nur verlustfrei", pt: "Apenas sem perdas", it: "Solo Lossless",
            nl: "Alleen lossless", ru: "Только без потерь", pl: "Tylko bezstratne", tr: "Yalnızca kayıpsız", sv: "Endast förlustfria", nb: "Bare tapsfrie",
            da: "Kun tabsfrie", fi: "Vain häviöttömät", zh: "仅无损", ja: "ロスレスのみ", ko: "무손실만"
        ),
        .smart_hires_only: tr(
            en: "Hi-Res Lossless Only", es: "Solo Hi-Res sin pérdida", fr: "Hi-Res Lossless uniquement", de: "Nur Hi-Res Lossless", pt: "Apenas Hi-Res sem perdas", it: "Solo Hi-Res Lossless",
            nl: "Alleen Hi-Res Lossless", ru: "Только Hi-Res без потерь", pl: "Tylko Hi-Res bezstratne", tr: "Yalnızca Hi-Res kayıpsız", sv: "Endast Hi-Res förlustfria", nb: "Bare Hi-Res tapsfrie",
            da: "Kun Hi-Res tabsfrie", fi: "Vain Hi-Res häviöttömät", zh: "仅高解析度无损", ja: "ハイレゾロスレスのみ", ko: "고해상도 무손실만"
        ),
        .smart_downloaded_only: tr(
            en: "Downloaded Only", es: "Solo descargadas", fr: "Téléchargés uniquement", de: "Nur heruntergeladene", pt: "Apenas baixadas", it: "Solo scaricati",
            nl: "Alleen gedownload", ru: "Только загруженные", pl: "Tylko pobrane", tr: "Yalnızca indirilenler", sv: "Endast nedladdade", nb: "Bare nedlastede",
            da: "Kun downloadede", fi: "Vain ladatut", zh: "仅已下载", ja: "ダウンロード済みのみ", ko: "다운로드한 항목만"
        ),
        .smart_taste: tr(
            en: "Taste", es: "Gusto", fr: "Goût", de: "Geschmack", pt: "Gosto", it: "Gusto",
            nl: "Smaak", ru: "Вкус", pl: "Gust", tr: "Beğeni", sv: "Smak", nb: "Smak",
            da: "Smag", fi: "Maku", zh: "喜好", ja: "好み", ko: "취향"
        ),
        .smart_section_mix: tr(
            en: "Mix Options", es: "Opciones de mezcla", fr: "Options de mix", de: "Mix-Optionen", pt: "Opções de mistura", it: "Opzioni mix",
            nl: "Mixopties", ru: "Параметры микса", pl: "Opcje miksu", tr: "Karışım seçenekleri", sv: "Mixalternativ", nb: "Miksalternativer",
            da: "Mixindstillinger", fi: "Miksausasetukset", zh: "混合选项", ja: "ミックスオプション", ko: "믹스 옵션"
        ),
        .smart_sort: tr(
            en: "Sort", es: "Ordenar", fr: "Trier", de: "Sortieren", pt: "Ordenar", it: "Ordina",
            nl: "Sorteren", ru: "Сортировка", pl: "Sortuj", tr: "Sırala", sv: "Sortera", nb: "Sorter",
            da: "Sortér", fi: "Lajittele", zh: "排序", ja: "並べ替え", ko: "정렬"
        ),
        .smart_limit: tr(
            en: "Limit: %d songs", es: "Límite: %d canciones", fr: "Limite : %d titres", de: "Limit: %d Songs", pt: "Limite: %d músicas", it: "Limite: %d brani",
            nl: "Limiet: %d nummers", ru: "Лимит: %d песен", pl: "Limit: %d utworów", tr: "Sınır: %d şarkı", sv: "Gräns: %d låtar", nb: "Grense: %d låter",
            da: "Grænse: %d sange", fi: "Raja: %d kappaletta", zh: "上限：%d 首歌曲", ja: "上限: %d 曲", ko: "제한: %d곡"
        ),
        .smart_matching_now: tr(
            en: "%d matching songs right now", es: "%d canciones coinciden ahora", fr: "%d titres correspondent actuellement", de: "%d passende Songs aktuell", pt: "%d músicas correspondem agora", it: "%d brani corrispondono ora",
            nl: "%d overeenkomende nummers nu", ru: "%d подходящих песен сейчас", pl: "%d pasujących utworów teraz", tr: "Şu anda %d eşleşen şarkı", sv: "%d matchande låtar just nu", nb: "%d samsvarende låter nå",
            da: "%d matchende sange lige nu", fi: "%d osumaa juuri nyt", zh: "当前匹配 %d 首歌曲", ja: "現在 %d 曲が一致", ko: "현재 일치하는 곡 %d개"
        ),
        .smart_any: tr(
            en: "Any", es: "Cualquiera", fr: "Tous", de: "Beliebig", pt: "Qualquer", it: "Qualsiasi",
            nl: "Elk", ru: "Любой", pl: "Dowolny", tr: "Herhangi", sv: "Valfri", nb: "Alle",
            da: "Enhver", fi: "Mikä tahansa", zh: "任意", ja: "すべて", ko: "모두"
        ),

        // MARK: Smart playlist enum cases
        .create_kind_custom: tr(
            en: "Custom", es: "Personalizada", fr: "Personnalisée", de: "Eigene", pt: "Personalizada", it: "Personalizzata",
            nl: "Aangepast", ru: "Свой", pl: "Własna", tr: "Özel", sv: "Anpassad", nb: "Egendefinert",
            da: "Tilpasset", fi: "Mukautettu", zh: "自定义", ja: "カスタム", ko: "사용자 지정"
        ),
        .create_kind_smart: tr(
            en: "Smart", es: "Inteligente", fr: "Intelligente", de: "Intelligent", pt: "Inteligente", it: "Smart",
            nl: "Slim", ru: "Умный", pl: "Inteligentna", tr: "Akıllı", sv: "Smart", nb: "Smart",
            da: "Smart", fi: "Älykäs", zh: "智能", ja: "スマート", ko: "스마트"
        ),
        .smart_match_all: tr(
            en: "All Rules", es: "Todas las reglas", fr: "Toutes les règles", de: "Alle Regeln", pt: "Todas as regras", it: "Tutte le regole",
            nl: "Alle regels", ru: "Все правила", pl: "Wszystkie reguły", tr: "Tüm kurallar", sv: "Alla regler", nb: "Alle regler",
            da: "Alle regler", fi: "Kaikki säännöt", zh: "所有规则", ja: "すべてのルール", ko: "모든 규칙"
        ),
        .smart_match_any: tr(
            en: "Any Rule", es: "Cualquier regla", fr: "N’importe quelle règle", de: "Beliebige Regel", pt: "Qualquer regra", it: "Qualsiasi regola",
            nl: "Elke regel", ru: "Любое правило", pl: "Dowolna reguła", tr: "Herhangi bir kural", sv: "Valfri regel", nb: "Hvilken som helst regel",
            da: "Enhver regel", fi: "Mikä tahansa sääntö", zh: "任意规则", ja: "いずれかのルール", ko: "임의 규칙"
        ),
        .smart_taste_loved: tr(
            en: "Loved", es: "Favoritas", fr: "Coups de cœur", de: "Geliebt", pt: "Adoradas", it: "Preferiti",
            nl: "Geliefd", ru: "Любимые", pl: "Ulubione", tr: "Sevilenler", sv: "Älskade", nb: "Elsket",
            da: "Elskede", fi: "Rakastetut", zh: "喜爱", ja: "お気に入り", ko: "좋아함"
        ),
        .smart_taste_not_disliked: tr(
            en: "Not Disliked", es: "No rechazadas", fr: "Non rejetés", de: "Nicht abgelehnt", pt: "Não rejeitadas", it: "Non rifiutati",
            nl: "Niet afgekeurd", ru: "Не отклонённые", pl: "Nieodrzucone", tr: "Beğenilmeyenler hariç", sv: "Inte ogillade", nb: "Ikke mislikt",
            da: "Ikke mislidte", fi: "Ei tykätyt pois", zh: "未不喜欢", ja: "嫌いでない", ko: "싫어하지 않음"
        ),
        .smart_taste_disliked: tr(
            en: "Disliked", es: "Rechazadas", fr: "Rejetés", de: "Abgelehnt", pt: "Rejeitadas", it: "Rifiutati",
            nl: "Afgekeurd", ru: "Отклонённые", pl: "Odrzucone", tr: "Beğenilmeyenler", sv: "Ogillade", nb: "Mislikt",
            da: "Mislidte", fi: "Ei pidetyt", zh: "不喜欢", ja: "嫌い", ko: "싫어함"
        ),
        .smart_sort_title: tr(
            en: "Title", es: "Título", fr: "Titre", de: "Titel", pt: "Título", it: "Titolo",
            nl: "Titel", ru: "Название", pl: "Tytuł", tr: "Başlık", sv: "Titel", nb: "Tittel",
            da: "Titel", fi: "Nimi", zh: "标题", ja: "タイトル", ko: "제목"
        ),
        .smart_sort_newest: tr(
            en: "Newest", es: "Más recientes", fr: "Plus récents", de: "Neueste", pt: "Mais recentes", it: "Più recenti",
            nl: "Nieuwste", ru: "Сначала новые", pl: "Najnowsze", tr: "En yeni", sv: "Nyaste", nb: "Nyeste",
            da: "Nyeste", fi: "Uusimmat", zh: "最新", ja: "新しい順", ko: "최신순"
        ),
        .smart_sort_oldest: tr(
            en: "Oldest", es: "Más antiguas", fr: "Plus anciens", de: "Älteste", pt: "Mais antigas", it: "Più vecchi",
            nl: "Oudste", ru: "Сначала старые", pl: "Najstarsze", tr: "En eski", sv: "Äldsta", nb: "Eldste",
            da: "Ældste", fi: "Vanhimmat", zh: "最旧", ja: "古い順", ko: "오래된순"
        ),
        .smart_sort_least_played: tr(
            en: "Least Played", es: "Menos reproducidas", fr: "Les moins écoutés", de: "Am wenigsten gespielt", pt: "Menos reproduzidas", it: "Meno riprodotti",
            nl: "Minst afgespeeld", ru: "Редко играемые", pl: "Najrzadziej odtwarzane", tr: "En az çalınan", sv: "Minst spelade", nb: "Minst spilt",
            da: "Mindst afspillet", fi: "Vähiten toistetut", zh: "最少播放", ja: "再生回数が少ない順", ko: "적게 재생됨"
        ),
        .smart_sort_random: tr(
            en: "Random", es: "Aleatorio", fr: "Aléatoire", de: "Zufällig", pt: "Aleatório", it: "Casuale",
            nl: "Willekeurig", ru: "Случайно", pl: "Losowo", tr: "Rastgele", sv: "Slumpmässig", nb: "Tilfeldig",
            da: "Tilfældig", fi: "Satunnainen", zh: "随机", ja: "ランダム", ko: "무작위"
        ),
        .smart_mix: tr(
            en: "Smart mix", es: "Mezcla inteligente", fr: "Mix intelligent", de: "Smarter Mix", pt: "Mix inteligente", it: "Mix intelligente",
            nl: "Slimme mix", ru: "Умный микс", pl: "Inteligentny miks", tr: "Akıllı karışım", sv: "Smart mix", nb: "Smart miks",
            da: "Smart mix", fi: "Älykäs miksaus", zh: "智能混合", ja: "スマートミックス", ko: "스마트 믹스"
        ),
        .smart_n_selected: tr(
            en: "%d selected", es: "%d seleccionados", fr: "%d sélectionnés", de: "%d ausgewählt", pt: "%d selecionados", it: "%d selezionati",
            nl: "%d geselecteerd", ru: "Выбрано: %d", pl: "Wybrano %d", tr: "%d seçili", sv: "%d valda", nb: "%d valgt",
            da: "%d valgt", fi: "%d valittu", zh: "已选 %d 个", ja: "%d 件選択", ko: "%d개 선택됨"
        ),
        .dup_playlist: tr(
            en: "A playlist named “%@” already exists.", es: "Ya existe una lista llamada «%@».", fr: "Une playlist nommée « %@ » existe déjà.", de: "Eine Playlist namens „%@“ existiert bereits.", pt: "Já existe uma lista chamada “%@”.", it: "Esiste già una playlist chiamata “%@”.",
            nl: "Er bestaat al een afspeellijst met de naam “%@”.", ru: "Плейлист с именем «%@» уже существует.", pl: "Playlista o nazwie „%@” już istnieje.", tr: "“%@” adlı bir çalma listesi zaten var.", sv: "En spellista med namnet ”%@” finns redan.", nb: "En spilleliste med navnet «%@» finnes allerede.",
            da: "En playliste med navnet “%@” findes allerede.", fi: "Soittolista nimeltä ”%@” on jo olemassa.", zh: "已存在名为“%@”的播放列表。", ja: "「%@」という名前のプレイリストは既に存在します。", ko: "“%@”(이)라는 재생목록이 이미 있습니다."
        ),
        .dup_smart: tr(
            en: "A smart playlist named “%@” already exists.", es: "Ya existe una lista inteligente llamada «%@».", fr: "Une playlist intelligente nommée « %@ » existe déjà.", de: "Eine intelligente Playlist namens „%@“ existiert bereits.", pt: "Já existe uma lista inteligente chamada “%@”.", it: "Esiste già una playlist smart chiamata “%@”.",
            nl: "Er bestaat al een slimme afspeellijst met de naam “%@”.", ru: "Умный плейлист с именем «%@» уже существует.", pl: "Inteligentna playlista o nazwie „%@” już istnieje.", tr: "“%@” adlı bir akıllı çalma listesi zaten var.", sv: "En smart spellista med namnet ”%@” finns redan.", nb: "En smart spilleliste med navnet «%@» finnes allerede.",
            da: "En smart playliste med navnet “%@” findes allerede.", fi: "Älykäs soittolista nimeltä ”%@” on jo olemassa.", zh: "已存在名为“%@”的智能播放列表。", ja: "「%@」という名前のスマートプレイリストは既に存在します。", ko: "“%@”(이)라는 스마트 재생목록이 이미 있습니다."
        ),
        .dup_folder: tr(
            en: "A folder named “%@” already exists.", es: "Ya existe una carpeta llamada «%@».", fr: "Un dossier nommé « %@ » existe déjà.", de: "Ein Ordner namens „%@“ existiert bereits.", pt: "Já existe uma pasta chamada “%@”.", it: "Esiste già una cartella chiamata “%@”.",
            nl: "Er bestaat al een map met de naam “%@”.", ru: "Папка с именем «%@» уже существует.", pl: "Folder o nazwie „%@” już istnieje.", tr: "“%@” adlı bir klasör zaten var.", sv: "En mapp med namnet ”%@” finns redan.", nb: "En mappe med navnet «%@» finnes allerede.",
            da: "En mappe med navnet “%@” findes allerede.", fi: "Kansio nimeltä ”%@” on jo olemassa.", zh: "已存在名为“%@”的文件夹。", ja: "「%@」という名前のフォルダは既に存在します。", ko: "“%@”(이)라는 폴더가 이미 있습니다."
        ),

        // MARK: Playlist detail / edit
        .playlist_edit_title: tr(
            en: "Edit Playlist", es: "Editar lista", fr: "Modifier la playlist", de: "Playlist bearbeiten", pt: "Editar lista", it: "Modifica playlist",
            nl: "Afspeellijst bewerken", ru: "Изменить плейлист", pl: "Edytuj playlistę", tr: "Çalma listesini düzenle", sv: "Redigera spellista", nb: "Rediger spilleliste",
            da: "Rediger playliste", fi: "Muokkaa soittolistaa", zh: "编辑播放列表", ja: "プレイリストを編集", ko: "재생목록 편집"
        ),
        .playlist_add_description: tr(
            en: "Add a description", es: "Añadir una descripción", fr: "Ajouter une description", de: "Beschreibung hinzufügen", pt: "Adicionar uma descrição", it: "Aggiungi una descrizione",
            nl: "Beschrijving toevoegen", ru: "Добавить описание", pl: "Dodaj opis", tr: "Açıklama ekle", sv: "Lägg till en beskrivning", nb: "Legg til en beskrivelse",
            da: "Tilføj en beskrivelse", fi: "Lisää kuvaus", zh: "添加描述", ja: "説明を追加", ko: "설명 추가"
        ),
        .playlist_remove_from: tr(
            en: "Remove from Playlist", es: "Quitar de la lista", fr: "Retirer de la playlist", de: "Aus Playlist entfernen", pt: "Remover da lista", it: "Rimuovi dalla playlist",
            nl: "Uit afspeellijst verwijderen", ru: "Убрать из плейлиста", pl: "Usuń z playlisty", tr: "Çalma listesinden çıkar", sv: "Ta bort från spellista", nb: "Fjern fra spilleliste",
            da: "Fjern fra playliste", fi: "Poista soittolistalta", zh: "从播放列表移除", ja: "プレイリストから削除", ko: "재생목록에서 제거"
        ),

        // MARK: Now Playing + sleep timer + audio signal path
        .player_mixing: tr(
            en: "Mixing", es: "Mezclando", fr: "Mixage", de: "Übergang", pt: "A misturar", it: "Mix in corso",
            nl: "Mixen", ru: "Микширование", pl: "Miksowanie", tr: "Miksleniyor", sv: "Mixar", nb: "Mikser",
            da: "Mixer", fi: "Miksataan", zh: "混音中", ja: "ミックス中", ko: "믹싱 중"
        ),
        .player_not_playing: tr(
            en: "Not Playing", es: "No se reproduce", fr: "Rien en lecture", de: "Keine Wiedergabe", pt: "Nada a reproduzir", it: "Nessuna riproduzione",
            nl: "Speelt niet", ru: "Не воспроизводится", pl: "Nic nie gra", tr: "Çalmıyor", sv: "Spelas inte", nb: "Spiller ikke",
            da: "Afspiller ikke", fi: "Ei toisteta", zh: "未播放", ja: "再生していません", ko: "재생 중 아님"
        ),
        .sleep_cancel_end_of_track: tr(
            en: "Cancel (end of track)", es: "Cancelar (fin de pista)", fr: "Annuler (fin du titre)", de: "Abbrechen (Titelende)", pt: "Cancelar (fim da faixa)", it: "Annulla (fine brano)",
            nl: "Annuleren (einde nummer)", ru: "Отменить (конец трека)", pl: "Anuluj (koniec utworu)", tr: "İptal et (parça sonu)", sv: "Avbryt (slut på spåret)", nb: "Avbryt (slutt på sporet)",
            da: "Annuller (slut på nummeret)", fi: "Peruuta (kappaleen lopussa)", zh: "取消（曲目结束）", ja: "キャンセル（曲の終了時）", ko: "취소(트랙 끝)"
        ),
        .sleep_cancel_timer: tr(
            en: "Cancel Timer", es: "Cancelar temporizador", fr: "Annuler le minuteur", de: "Timer abbrechen", pt: "Cancelar temporizador", it: "Annulla timer",
            nl: "Timer annuleren", ru: "Отменить таймер", pl: "Anuluj minutnik", tr: "Zamanlayıcıyı iptal et", sv: "Avbryt timer", nb: "Avbryt timer",
            da: "Annuller timer", fi: "Peruuta ajastin", zh: "取消计时器", ja: "タイマーをキャンセル", ko: "타이머 취소"
        ),
        .sleep_minutes: tr(
            en: "%d minutes", es: "%d min", fr: "%d min", de: "%d Min.", pt: "%d min", it: "%d min",
            nl: "%d min", ru: "%d мин", pl: "%d min", tr: "%d dk", sv: "%d min", nb: "%d min",
            da: "%d min", fi: "%d min", zh: "%d 分钟", ja: "%d分", ko: "%d분"
        ),
        .sleep_end_of_track: tr(
            en: "End of Track", es: "Fin de pista", fr: "Fin du titre", de: "Titelende", pt: "Fim da faixa", it: "Fine brano",
            nl: "Einde nummer", ru: "Конец трека", pl: "Koniec utworu", tr: "Parça sonu", sv: "Slut på spåret", nb: "Slutt på sporet",
            da: "Slut på nummeret", fi: "Kappaleen loppu", zh: "曲目结束", ja: "曲の終了時", ko: "트랙 끝"
        ),
        .action_yes: tr(
            en: "Yes", es: "Sí", fr: "Oui", de: "Ja", pt: "Sim", it: "Sì",
            nl: "Ja", ru: "Да", pl: "Tak", tr: "Evet", sv: "Ja", nb: "Ja",
            da: "Ja", fi: "Kyllä", zh: "是", ja: "はい", ko: "예"
        ),
        .action_no: tr(
            en: "No", es: "No", fr: "Non", de: "Nein", pt: "Não", it: "No",
            nl: "Nee", ru: "Нет", pl: "Nie", tr: "Hayır", sv: "Nej", nb: "Nei",
            da: "Nej", fi: "Ei", zh: "否", ja: "いいえ", ko: "아니요"
        ),
        .action_on: tr(
            en: "On", es: "Activado", fr: "Activé", de: "Ein", pt: "Ativado", it: "Attivo",
            nl: "Aan", ru: "Вкл.", pl: "Wł.", tr: "Açık", sv: "På", nb: "På",
            da: "Til", fi: "Päällä", zh: "开启", ja: "オン", ko: "켜짐"
        ),
        .action_off: tr(
            en: "Off", es: "Desactivado", fr: "Désactivé", de: "Aus", pt: "Desativado", it: "Disattivo",
            nl: "Uit", ru: "Выкл.", pl: "Wył.", tr: "Kapalı", sv: "Av", nb: "Av",
            da: "Fra", fi: "Pois", zh: "关闭", ja: "オフ", ko: "꺼짐"
        ),
        .media_equalizer: tr(
            en: "Equalizer", es: "Ecualizador", fr: "Égaliseur", de: "Equalizer", pt: "Equalizador", it: "Equalizzatore",
            nl: "Equalizer", ru: "Эквалайзер", pl: "Korektor", tr: "Ekolayzer", sv: "Equalizer", nb: "Equalizer",
            da: "Equalizer", fi: "Taajuuskorjain", zh: "均衡器", ja: "イコライザ", ko: "이퀄라이저"
        ),
        .detail_bitrate: tr(
            en: "Bitrate", es: "Tasa de bits", fr: "Débit", de: "Bitrate", pt: "Taxa de bits", it: "Bitrate",
            nl: "Bitsnelheid", ru: "Битрейт", pl: "Szybkość bitowa", tr: "Bit hızı", sv: "Bithastighet", nb: "Bithastighet",
            da: "Bithastighed", fi: "Bittinopeus", zh: "比特率", ja: "ビットレート", ko: "비트 전송률"
        ),
        .detail_sample_rate: tr(
            en: "Sample Rate", es: "Frecuencia de muestreo", fr: "Fréquence d'échantillonnage", de: "Samplerate", pt: "Taxa de amostragem", it: "Frequenza di campionamento",
            nl: "Samplefrequentie", ru: "Частота дискретизации", pl: "Częstotliwość próbkowania", tr: "Örnekleme hızı", sv: "Samplingsfrekvens", nb: "Samplingsrate",
            da: "Samplingsfrekvens", fi: "Näytteenottotaajuus", zh: "采样率", ja: "サンプルレート", ko: "샘플 레이트"
        ),
        .detail_bit_depth: tr(
            en: "Bit Depth", es: "Profundidad de bits", fr: "Profondeur de bits", de: "Bittiefe", pt: "Profundidade de bits", it: "Profondità bit",
            nl: "Bitdiepte", ru: "Битовая глубина", pl: "Głębia bitowa", tr: "Bit derinliği", sv: "Bitdjup", nb: "Bitdybde",
            da: "Bitdybde", fi: "Bittisyvyys", zh: "位深", ja: "ビット深度", ko: "비트 깊이"
        ),
        .signal_lossless_audio: tr(
            en: "Lossless Audio", es: "Audio sin pérdida", fr: "Audio sans perte", de: "Verlustfreies Audio", pt: "Áudio sem perdas", it: "Audio lossless",
            nl: "Lossless audio", ru: "Аудио без потерь", pl: "Dźwięk bezstratny", tr: "Kayıpsız ses", sv: "Förlustfritt ljud", nb: "Tapsfri lyd",
            da: "Tabsfri lyd", fi: "Häviötön ääni", zh: "无损音频", ja: "ロスレスオーディオ", ko: "무손실 오디오"
        ),
        .signal_output: tr(
            en: "Output", es: "Salida", fr: "Sortie", de: "Ausgabe", pt: "Saída", it: "Uscita",
            nl: "Uitvoer", ru: "Выход", pl: "Wyjście", tr: "Çıkış", sv: "Utgång", nb: "Utgang",
            da: "Udgang", fi: "Lähtö", zh: "输出", ja: "出力", ko: "출력"
        ),
        .signal_system_output: tr(
            en: "System Output", es: "Salida del sistema", fr: "Sortie système", de: "Systemausgabe", pt: "Saída do sistema", it: "Uscita di sistema",
            nl: "Systeemuitvoer", ru: "Системный выход", pl: "Wyjście systemowe", tr: "Sistem çıkışı", sv: "Systemutgång", nb: "Systemutgang",
            da: "Systemudgang", fi: "Järjestelmälähtö", zh: "系统输出", ja: "システム出力", ko: "시스템 출력"
        ),
        .signal_path_title: tr(
            en: "Audio Signal Path", es: "Ruta de la señal de audio", fr: "Chemin du signal audio", de: "Audiosignalpfad", pt: "Caminho do sinal de áudio", it: "Percorso segnale audio",
            nl: "Audiosignaalpad", ru: "Путь аудиосигнала", pl: "Ścieżka sygnału audio", tr: "Ses sinyal yolu", sv: "Ljudsignalväg", nb: "Lydsignalvei",
            da: "Lydsignalvej", fi: "Äänisignaalin polku", zh: "音频信号路径", ja: "オーディオ信号パス", ko: "오디오 신호 경로"
        ),
        .signal_source_file: tr(
            en: "Source File", es: "Archivo fuente", fr: "Fichier source", de: "Quelldatei", pt: "Ficheiro de origem", it: "File sorgente",
            nl: "Bronbestand", ru: "Исходный файл", pl: "Plik źródłowy", tr: "Kaynak dosya", sv: "Källfil", nb: "Kildefil",
            da: "Kildefil", fi: "Lähdetiedosto", zh: "源文件", ja: "ソースファイル", ko: "원본 파일"
        ),
        .signal_server_stream: tr(
            en: "Server Stream", es: "Flujo del servidor", fr: "Flux serveur", de: "Serverstream", pt: "Stream do servidor", it: "Stream server",
            nl: "Serverstream", ru: "Поток сервера", pl: "Strumień z serwera", tr: "Sunucu akışı", sv: "Serverström", nb: "Serverstrøm",
            da: "Serverstream", fi: "Palvelimen striimi", zh: "服务器串流", ja: "サーバーストリーム", ko: "서버 스트림"
        ),
        .signal_transcoding: tr(
            en: "Transcoding", es: "Transcodificación", fr: "Transcodage", de: "Transkodierung", pt: "Transcodificação", it: "Transcodifica",
            nl: "Transcoderen", ru: "Транскодирование", pl: "Transkodowanie", tr: "Kod dönüştürme", sv: "Omkodning", nb: "Omkoding",
            da: "Transkodning", fi: "Transkoodaus", zh: "转码", ja: "トランスコード", ko: "트랜스코딩"
        ),
        .signal_original: tr(
            en: "Original", es: "Original", fr: "Original", de: "Original", pt: "Original", it: "Originale",
            nl: "Origineel", ru: "Оригинал", pl: "Oryginał", tr: "Orijinal", sv: "Original", nb: "Original",
            da: "Original", fi: "Alkuperäinen", zh: "原始", ja: "オリジナル", ko: "원본"
        ),
        .signal_wifi_quality: tr(
            en: "Wi-Fi Quality", es: "Calidad Wi-Fi", fr: "Qualité Wi-Fi", de: "WLAN-Qualität", pt: "Qualidade Wi-Fi", it: "Qualità Wi-Fi",
            nl: "Wifi-kwaliteit", ru: "Качество Wi-Fi", pl: "Jakość Wi-Fi", tr: "Wi-Fi kalitesi", sv: "Wi-Fi-kvalitet", nb: "Wi-Fi-kvalitet",
            da: "Wi-Fi-kvalitet", fi: "Wi-Fi-laatu", zh: "Wi-Fi 质量", ja: "Wi-Fi品質", ko: "Wi-Fi 품질"
        ),
        .signal_cellular_quality: tr(
            en: "Cellular Quality", es: "Calidad móvil", fr: "Qualité cellulaire", de: "Mobilfunkqualität", pt: "Qualidade móvel", it: "Qualità cellulare",
            nl: "Mobiele kwaliteit", ru: "Качество сотовой сети", pl: "Jakość sieci komórkowej", tr: "Hücresel kalite", sv: "Mobilnätskvalitet", nb: "Mobilkvalitet",
            da: "Mobilkvalitet", fi: "Mobiililaatu", zh: "蜂窝网络质量", ja: "モバイル通信品質", ko: "셀룰러 품질"
        ),
        .signal_same_as_wifi: tr(
            en: "Same as Wi-Fi", es: "Igual que Wi-Fi", fr: "Comme le Wi-Fi", de: "Wie WLAN", pt: "Igual ao Wi-Fi", it: "Come Wi-Fi",
            nl: "Zelfde als wifi", ru: "Как Wi-Fi", pl: "Tak jak Wi-Fi", tr: "Wi-Fi ile aynı", sv: "Samma som Wi-Fi", nb: "Samme som Wi-Fi",
            da: "Samme som Wi-Fi", fi: "Sama kuin Wi-Fi", zh: "与 Wi-Fi 相同", ja: "Wi-Fiと同じ", ko: "Wi-Fi와 동일"
        ),
        .signal_app_processing: tr(
            en: "App Processing", es: "Procesamiento de la app", fr: "Traitement par l'app", de: "App-Verarbeitung", pt: "Processamento da app", it: "Elaborazione app",
            nl: "App-verwerking", ru: "Обработка в приложении", pl: "Przetwarzanie w aplikacji", tr: "Uygulama işleme", sv: "Appbearbetning", nb: "Appbehandling",
            da: "Appbehandling", fi: "Sovelluksen käsittely", zh: "应用处理", ja: "アプリ処理", ko: "앱 처리"
        ),
        .signal_volume_norm: tr(
            en: "Volume Normalization", es: "Normalización de volumen", fr: "Normalisation du volume", de: "Lautstärkenormalisierung", pt: "Normalização de volume", it: "Normalizzazione volume",
            nl: "Volumenormalisatie", ru: "Нормализация громкости", pl: "Normalizacja głośności", tr: "Ses normalizasyonu", sv: "Volymnormalisering", nb: "Volumnormalisering",
            da: "Lydstyrkenormalisering", fi: "Äänenvoimakkuuden normalisointi", zh: "音量标准化", ja: "音量ノーマライズ", ko: "음량 정규화"
        ),
        .signal_port_type: tr(
            en: "Port Type", es: "Tipo de puerto", fr: "Type de port", de: "Porttyp", pt: "Tipo de porta", it: "Tipo di porta",
            nl: "Poorttype", ru: "Тип порта", pl: "Typ portu", tr: "Bağlantı noktası türü", sv: "Porttyp", nb: "Porttype",
            da: "Porttype", fi: "Portin tyyppi", zh: "端口类型", ja: "ポートタイプ", ko: "포트 유형"
        ),
        .signal_output_sample_rate: tr(
            en: "Output Sample Rate", es: "Frecuencia de salida", fr: "Fréquence de sortie", de: "Ausgabe-Samplerate", pt: "Taxa de amostragem de saída", it: "Frequenza di uscita",
            nl: "Uitvoer-samplefrequentie", ru: "Частота дискретизации выхода", pl: "Częstotliwość próbkowania wyjścia", tr: "Çıkış örnekleme hızı", sv: "Utgående samplingsfrekvens", nb: "Samplingsrate for utgang",
            da: "Samplingsfrekvens for output", fi: "Lähdön näytteenottotaajuus", zh: "输出采样率", ja: "出力サンプルレート", ko: "출력 샘플 레이트"
        ),
        .signal_output_channels: tr(
            en: "Output Channels", es: "Canales de salida", fr: "Canaux de sortie", de: "Ausgabekanäle", pt: "Canais de saída", it: "Canali di uscita",
            nl: "Uitvoerkanalen", ru: "Выходные каналы", pl: "Kanały wyjściowe", tr: "Çıkış kanalları", sv: "Utgångskanaler", nb: "Utgangskanaler",
            da: "Outputkanaler", fi: "Lähtökanavat", zh: "输出声道", ja: "出力チャンネル", ko: "출력 채널"
        ),
        .signal_result: tr(
            en: "Result", es: "Resultado", fr: "Résultat", de: "Ergebnis", pt: "Resultado", it: "Risultato",
            nl: "Resultaat", ru: "Результат", pl: "Wynik", tr: "Sonuç", sv: "Resultat", nb: "Resultat",
            da: "Resultat", fi: "Tulos", zh: "结果", ja: "結果", ko: "결과"
        ),
        .signal_badge: tr(
            en: "Badge", es: "Insignia", fr: "Badge", de: "Badge", pt: "Distintivo", it: "Badge",
            nl: "Badge", ru: "Значок", pl: "Odznaka", tr: "Rozet", sv: "Märke", nb: "Merke",
            da: "Badge", fi: "Merkki", zh: "徽章", ja: "バッジ", ko: "배지"
        ),
        .signal_not_lossless: tr(
            en: "Not lossless", es: "No es sin pérdida", fr: "Pas sans perte", de: "Nicht verlustfrei", pt: "Não é sem perdas", it: "Non lossless",
            nl: "Niet lossless", ru: "Не без потерь", pl: "Nie jest bezstratny", tr: "Kayıpsız değil", sv: "Inte förlustfri", nb: "Ikke tapsfri",
            da: "Ikke tabsfri", fi: "Ei häviötön", zh: "非无损", ja: "ロスレスではありません", ko: "무손실 아님"
        ),
        .signal_why: tr(
            en: "Why", es: "Motivo", fr: "Pourquoi", de: "Grund", pt: "Motivo", it: "Perché",
            nl: "Waarom", ru: "Причина", pl: "Powód", tr: "Neden", sv: "Varför", nb: "Hvorfor",
            da: "Hvorfor", fi: "Syy", zh: "原因", ja: "理由", ko: "이유"
        ),
    ]
}
