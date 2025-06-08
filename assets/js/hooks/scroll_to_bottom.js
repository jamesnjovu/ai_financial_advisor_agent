// Scroll to bottom hook for messages
const ScrollToBottom = {
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

export default ScrollToBottom;
