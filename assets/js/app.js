// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

// Auto-resize textarea hook
Hooks.AutoResize = {
  mounted() {
    this.el.addEventListener("input", () => {
      // Reset height to auto to get the correct scrollHeight
      this.el.style.height = "auto"
      // Set height to scrollHeight (up to max-height)
      this.el.style.height = Math.min(this.el.scrollHeight, 120) + "px"
    })

    // Handle Enter key to submit (Shift+Enter for new line)
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        // Find and trigger the form submission
        const form = this.el.closest("form")
        if (form) {
          const event = new Event("submit", { bubbles: true, cancelable: true })
          form.dispatchEvent(event)
        }
      }
    })
  }
}

// Scroll to bottom hook for messages
Hooks.ScrollToBottom = {
  mounted() {
    this.scrollToBottom()
  },

  updated() {
    this.scrollToBottom()
  },

  scrollToBottom() {
    // Small delay to ensure DOM is updated
    setTimeout(() => {
      this.el.scrollTop = this.el.scrollHeight
    }, 10)
  }
}

// Update the LiveSocket initialization to include hooks

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

