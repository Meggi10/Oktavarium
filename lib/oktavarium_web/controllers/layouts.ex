defmodule OktavariumWeb.Layouts do
  @moduledoc false
  use OktavariumWeb, :html

  attr :page_title, :string, default: nil
  slot :inner_block, required: true

  @doc "Dokument wspólny dla stron publicznych, Pracowni i błędów."
  def document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="dark" />
        <title>{if @page_title, do: @page_title <> " | Oktavarium", else: "Oktavarium"}</title>
        <link rel="icon" href={~p"/favicon.svg"} type="image/svg+xml" />
        <link rel="stylesheet" href={~p"/assets/app.css"} />
        <script type="module" src={~p"/assets/js/lib/copy-id.js"}>
        </script>
      </head>
      <body>
        <a class="skip" href="#main">Przejdź do treści</a>
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end

  attr :active, :string, default: nil
  slot :inner_block, required: true

  @doc "Nawigacja nie wymaga sesji. Pracownia sama obsługuje logowanie."
  def shell(assigns) do
    ~H"""
    <header class="top">
      <a class="wordmark" href={~p"/"} aria-label="Oktavarium — strona główna">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 236 48"
          width="177"
          height="36"
          style="display: block; flex-shrink: 0;"
          aria-hidden="true"
          focusable="false"
        >
          <g fill="currentColor">
            <!-- Sygnet: dwa splecione ogniwa -->
            <path d="M17 4H29L39 14L29 24L24 19L30 13L26 9H20L9 20V26L13 30L19 24L24 29L14 39L4 29V17Z" />
            <path
              d="M17 4H29L39 14L29 24L24 19L30 13L26 9H20L9 20V26L13 30L19 24L24 29L14 39L4 29V17Z"
              transform="rotate(180 24 24)"
            />

            <!-- Napis zamieniony na ścieżki -->
            <path d="
    				M73.226 10.806C66.12 10.806 61.292 16.042 61.292 23.794C61.292 31.58 66.086 36.782 73.26 36.782C76.286 36.782 78.938 35.864 80.944 34.164C83.63 31.886 85.228 28.044 85.228 23.998C85.228 16.008 80.502 10.806 73.226 10.806Z
    				M73.226 13.594C78.598 13.594 82.066 17.64 82.066 23.93C82.066 29.914 78.496 33.994 73.26 33.994C67.956 33.994 64.454 29.914 64.454 23.794C64.454 17.674 67.956 13.594 73.226 13.594Z

    				M90.846 11.214H88.024V36H90.846V29.064L93.6 26.344L99.618 36H103.12L95.844 24.338L102.032 18.184H98.394L90.846 25.732Z

    				M111.288 18.184H108.364V13.288H105.542V18.184H103.128V20.496H105.542V33.96C105.542 35.796 106.766 36.782 108.976 36.782C109.724 36.782 110.336 36.714 111.288 36.544V34.164C110.88 34.266 110.506 34.3 109.928 34.3C108.704 34.3 108.364 33.96 108.364 32.702V20.496H111.288Z

    				M129.894 34.334C129.588 34.402 129.452 34.402 129.282 34.402C128.296 34.402 127.752 33.892 127.752 33.008V22.536C127.752 19.374 125.44 17.674 121.054 17.674C118.436 17.674 116.362 18.422 115.138 19.748C114.322 20.666 113.982 21.686 113.914 23.454H116.77C117.008 21.278 118.3 20.292 120.952 20.292C123.536 20.292 124.93 21.244 124.93 22.944V23.692C124.896 24.916 124.284 25.358 121.972 25.664C117.96 26.174 117.348 26.31 116.26 26.752C114.186 27.636 113.132 29.2 113.132 31.512C113.132 34.742 115.376 36.782 118.98 36.782C121.224 36.782 123.026 36 125.032 34.164C125.236 36 126.12 36.782 127.956 36.782C128.568 36.782 128.942 36.714 129.894 36.476Z
    				M124.93 30.39C124.93 31.342 124.658 31.92 123.808 32.702C122.652 33.756 121.258 34.3 119.592 34.3C117.382 34.3 116.09 33.246 116.09 31.444C116.09 29.574 117.314 28.622 120.374 28.18C123.4 27.772 123.978 27.636 124.93 27.194Z

    				M139.898 36L146.732 18.184H143.536L138.504 32.634L133.744 18.184H130.548L136.804 36Z

    				M164.998 34.334C164.692 34.402 164.556 34.402 164.386 34.402C163.4 34.402 162.856 33.892 162.856 33.008V22.536C162.856 19.374 160.544 17.674 156.158 17.674C153.54 17.674 151.466 18.422 150.242 19.748C149.426 20.666 149.086 21.686 149.018 23.454H151.874C152.112 21.278 153.404 20.292 156.056 20.292C158.64 20.292 160.034 21.244 160.034 22.944V23.692C160 24.916 159.388 25.358 157.076 25.664C153.064 26.174 152.452 26.31 151.364 26.752C149.29 27.636 148.236 29.2 148.236 31.512C148.236 34.742 150.48 36.782 154.084 36.782C156.328 36.782 158.13 36 160.136 34.164C160.34 36 161.224 36.782 163.06 36.782C163.672 36.782 164.046 36.714 164.998 36.476Z
    				M160.034 30.39C160.034 31.342 159.762 31.92 158.912 32.702C157.756 33.756 156.362 34.3 154.696 34.3C152.486 34.3 151.194 33.246 151.194 31.444C151.194 29.574 152.418 28.622 155.478 28.18C158.504 27.772 159.082 27.636 160.034 27.194Z

    				M167.658 18.184V36H170.514V26.752C170.548 22.468 172.316 20.564 176.226 20.666V17.776C175.75 17.708 175.478 17.674 175.138 17.674C173.302 17.674 171.908 18.762 170.276 21.414V18.184Z

    				M181.334 18.184H178.512V36H181.334Z
    				M181.334 11.214H178.478V14.784H181.334Z

    				M199.77 36V18.184H196.948V28.282C196.948 31.92 195.044 34.3 192.086 34.3C189.842 34.3 188.414 32.94 188.414 30.798V18.184H185.592V31.92C185.592 34.878 187.802 36.782 191.27 36.782C193.888 36.782 195.554 35.864 197.22 33.518V36Z

    				M204.266 18.184V36H207.122V24.814C207.122 22.23 208.992 20.156 211.304 20.156C213.412 20.156 214.602 21.448 214.602 23.726V36H217.458V24.814C217.458 22.23 219.328 20.156 221.64 20.156C223.714 20.156 224.938 21.482 224.938 23.726V36H227.794V22.638C227.794 19.442 225.958 17.674 222.626 17.674C220.246 17.674 218.818 18.388 217.152 20.394C216.098 18.49 214.67 17.674 212.358 17.674C209.978 17.674 208.38 18.558 206.884 20.7V18.184Z
    			" />
          </g>
        </svg>
      </a>
      <nav class="main-nav" aria-label="Główna">
        <a href={~p"/"} aria-current={if @active == "/", do: "page"}>Odkrywaj</a>
        <a href={~p"/studio"} aria-current={if @active == "/studio", do: "page"}>Pracownia</a>
      </nav>
      <div class="nav-actions">
        <a class="nav-login" href={~p"/login"} aria-current={if @active == "/login", do: "page"}>
          Odblokuj klucze
        </a>
        <a class="btn primary" href={~p"/join"} aria-current={if @active == "/join", do: "page"}>
          Dołącz
        </a>
      </div>
    </header>
    <main id="main" tabindex="-1">{render_slot(@inner_block)}</main>
    """
  end

  def app(assigns) do
    assigns = Map.put(assigns, :active, if(assigns[:conn], do: assigns.conn.request_path))

    ~H"""
    <.shell active={@active}>{@inner_content}</.shell>
    """
  end

  def root(assigns) do
    ~H"""
    <.document page_title={assigns[:page_title]}>{@inner_content}</.document>
    """
  end
end
