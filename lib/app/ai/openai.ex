defmodule App.AI.OpenAI do
  @moduledoc """
  OpenAI API integration for chat completions and embeddings
  """
  @options [
    timeout: 2_000_000,
    recv_timeout: 2_000_000
  ]

  @base_url "https://api.openai.com/v1"

  def chat_completion(messages, opts \\ []) do
    config = Application.get_env(:app, :openai)

    payload = %{
      model: opts[:model] || config[:model] || "gpt-4",
      messages: messages,
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 2000
    }

    # Add tools if provided
    payload = if tools = opts[:tools] do
      Map.put(payload, :tools, tools)
    else
      payload
    end

    headers = [
      {"Authorization", "Bearer #{config[:api_key]}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post("#{@base_url}/chat/completions", Jason.encode!(payload), headers, @options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "OpenAI API error #{status}: #{body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  def create_embedding(text, opts \\ []) do
    config = Application.get_env(:app, :openai)

    payload = %{
      model: opts[:model] || "text-embedding-ada-002",
      input: text
    }

    headers = [
      {"Authorization", "Bearer #{config[:api_key]}"},
      {"Content-Type", "application/json"}
    ]

    case HTTPoison.post("#{@base_url}/embeddings", Jason.encode!(payload), headers, @options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        %{"data" => [%{"embedding" => embedding}]} = Jason.decode!(body)
        {:ok, embedding}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, "OpenAI API error #{status}: #{body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  def stream_completion(messages, callback, opts \\ []) do
    config = Application.get_env(:app, :openai)

    payload = %{
      model: opts[:model] || config[:model] || "gpt-4",
      messages: messages,
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 2000,
      stream: true
    }

    headers = [
      {"Authorization", "Bearer #{config[:api_key]}"},
      {"Content-Type", "application/json"}
    ]

    # This would need a proper streaming implementation
    # For now, fall back to regular completion
    case chat_completion(messages, opts) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}}]}} ->
        callback.(content)
        {:ok, :completed}

      error ->
        error
    end
  end
end
