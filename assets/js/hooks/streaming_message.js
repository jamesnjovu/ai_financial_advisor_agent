// Streaming message handler
const StreamingMessage = {
    mounted() {
        // Handle streaming chunk updates
        this.handleEvent("stream_chunk", ({message_id, chunk}) => {
            const messageElement = document.getElementById(`message-content-${message_id}`)
            if (messageElement) {
                messageElement.textContent += chunk
                // Scroll to bottom as content grows
                const container = document.getElementById("messages-container")
                if (container) {
                    container.scrollTop = container.scrollHeight
                }
            }
        })

        // Handle stream completion
        this.handleEvent("stream_complete", ({message_id}) => {
            const messageElement = document.getElementById(`message-content-${message_id}`)
            if (messageElement) {
                // Remove typing indicator if present
                const cursor = messageElement.parentElement.querySelector('.animate-pulse')
                if (cursor) {
                    cursor.remove()
                }
            }
        })

        // Handle tool calls execution
        this.handleEvent("tool_calls_executing", ({tool_calls}) => {
            console.log("Tools executing:", tool_calls)
            // You could show a UI indicator that tools are running
        })
    }
}
export default StreamingMessage;
