// Auto-resize textarea hook
const AutoResize = {
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

export default AutoResize;
