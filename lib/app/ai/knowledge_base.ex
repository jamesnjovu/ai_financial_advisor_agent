defmodule App.AI.KnowledgeBase do
  @moduledoc """
  RAG (Retrieval Augmented Generation) knowledge base for emails and HubSpot data
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Knowledge.KnowledgeEntry
  alias App.AI.OpenAI
  alias App.Integrations.{GmailClient, HubSpotClient}
  alias App.Accounts.User

  def search_relevant_content(%User{} = user, query, opts \\ []) do
    limit = opts[:limit] || 5

    # Create embedding for the query
    case OpenAI.create_embedding(query) do
      {:ok, query_embedding} ->
        # Search for similar content using vector similarity
        similar_entries =
          KnowledgeEntry
          |> where([k], k.user_id == ^user.id)
          |> limit(^limit)
          |> select([k], %{
            id: k.id,
            source_type: k.source_type,
            source_id: k.source_id,
            title: k.title,
            content: k.content,
            metadata: k.metadata,
            similarity: fragment("1 - (? <=> ?)", k.embedding, ^query_embedding)
          })
          |> order_by([k], desc: fragment("1 - (? <=> ?)", k.embedding, ^query_embedding))
          |> Repo.all()

        {:ok, similar_entries}

      {:error, reason} ->
        # Fallback to text search if embedding fails
        text_results =
          KnowledgeEntry
          |> where([k], k.user_id == ^user.id)
          |> where([k], ilike(k.content, ^"%#{query}%") or ilike(k.title, ^"%#{query}%"))
          |> limit(^limit)
          |> select([k], %{
            id: k.id,
            source_type: k.source_type,
            source_id: k.source_id,
            title: k.title,
            content: k.content,
            metadata: k.metadata,
            similarity: 0.5
          })
          |> Repo.all()

        {:ok, text_results}
    end
  end

  def sync_user_data(%User{} = user) do
    # Sync Gmail data
    gmail_sync_result = sync_gmail_data(user)

    # Sync HubSpot data
    hubspot_sync_result = sync_hubspot_data(user)

    {:ok, %{
      gmail: gmail_sync_result,
      hubspot: hubspot_sync_result
    }}
  end

  defp sync_gmail_data(%User{} = user) do
    case GmailClient.list_messages(user, max_results: 50) do
      {:ok, %{"messages" => messages}} when is_list(messages) ->
        synced_count =
          messages
          |> Enum.map(fn %{"id" => message_id} ->
            sync_email_message(user, message_id)
          end)
          |> Enum.count(&match?({:ok, _}, &1))

        {:ok, %{synced: synced_count, total: length(messages)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_email_message(%User{} = user, message_id) do
    # Check if already synced
    existing = Repo.get_by(KnowledgeEntry,
      user_id: user.id,
      source_type: "email",
      source_id: message_id
    )

    if existing do
      {:ok, existing}
    else
      case GmailClient.get_message(user, message_id) do
        {:ok, message} ->
          email_data = GmailClient.extract_email_data(message)

          content = """
          From: #{email_data.from}
          To: #{email_data.to}
          Subject: #{email_data.subject}
          Date: #{email_data.date}

          #{email_data.body}
          """

          case OpenAI.create_embedding(content) do
            {:ok, embedding} ->
              attrs = %{
                user_id: user.id,
                source_type: "email",
                source_id: message_id,
                title: email_data.subject || "No Subject",
                content: content,
                metadata: %{
                  from: email_data.from,
                  to: email_data.to,
                  date: email_data.date,
                  thread_id: email_data.thread_id
                },
                embedding: embedding,
                last_synced_at: DateTime.utc_now()
              }

              %KnowledgeEntry{}
              |> KnowledgeEntry.changeset(attrs)
              |> Repo.insert()

            {:error, _} ->
              # Store without embedding as fallback
              attrs = %{
                user_id: user.id,
                source_type: "email",
                source_id: message_id,
                title: email_data.subject || "No Subject",
                content: content,
                metadata: %{
                  from: email_data.from,
                  to: email_data.to,
                  date: email_data.date,
                  thread_id: email_data.thread_id
                },
                last_synced_at: DateTime.utc_now()
              }

              %KnowledgeEntry{}
              |> KnowledgeEntry.changeset(attrs)
              |> Repo.insert()
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp sync_hubspot_data(%User{} = user) do
    # Sync contacts
    contacts_result = sync_hubspot_contacts(user)

    {:ok, %{contacts: contacts_result}}
  end

  defp sync_hubspot_contacts(%User{} = user) do
    case HubSpotClient.get_contacts(user, limit: 100) do
      {:ok, %{"results" => contacts}} when is_list(contacts) ->
        synced_count =
          contacts
          |> Enum.map(fn contact ->
            sync_hubspot_contact(user, contact)
          end)
          |> Enum.count(&match?({:ok, _}, &1))

        {:ok, %{synced: synced_count, total: length(contacts)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_hubspot_contact(%User{} = user, contact) do
    contact_id = contact["id"]
    properties = contact["properties"] || %{}

    # Check if already synced
    existing = Repo.get_by(KnowledgeEntry,
      user_id: user.id,
      source_type: "hubspot_contact",
      source_id: contact_id
    )

    if existing do
      {:ok, existing}
    else
      content = """
      HubSpot Contact: #{properties["firstname"] || ""} #{properties["lastname"] || ""}
      Email: #{properties["email"] || ""}
      Company: #{properties["company"] || ""}
      Phone: #{properties["phone"] || ""}
      Created: #{properties["createdate"] || ""}
      Last Modified: #{properties["lastmodifieddate"] || ""}
      """

      case OpenAI.create_embedding(content) do
        {:ok, embedding} ->
          attrs = %{
            user_id: user.id,
            source_type: "hubspot_contact",
            source_id: contact_id,
            title: String.trim("#{properties["firstname"] || ""} #{properties["lastname"] || ""}"),
            content: content,
            metadata: properties,
            embedding: embedding,
            last_synced_at: DateTime.utc_now()
          }

          %KnowledgeEntry{}
          |> KnowledgeEntry.changeset(attrs)
          |> Repo.insert()

        {:error, _} ->
          # Store without embedding
          attrs = %{
            user_id: user.id,
            source_type: "hubspot_contact",
            source_id: contact_id,
            title: String.trim("#{properties["firstname"] || ""} #{properties["lastname"] || ""}"),
            content: content,
            metadata: properties,
            last_synced_at: DateTime.utc_now()
          }

          %KnowledgeEntry{}
          |> KnowledgeEntry.changeset(attrs)
          |> Repo.insert()
      end
    end
  end

  def get_sync_status(%User{} = user) do
    email_count =
      KnowledgeEntry
      |> where([k], k.user_id == ^user.id and k.source_type == "email")
      |> Repo.aggregate(:count, :id)

    hubspot_count =
      KnowledgeEntry
      |> where([k], k.user_id == ^user.id and k.source_type == "hubspot_contact")
      |> Repo.aggregate(:count, :id)

    last_sync =
      KnowledgeEntry
      |> where([k], k.user_id == ^user.id)
      |> order_by([k], desc: k.last_synced_at)
      |> limit(1)
      |> select([k], k.last_synced_at)
      |> Repo.one()

    %{
      total_entries: email_count + hubspot_count,
      email_entries: email_count,
      hubspot_entries: hubspot_count,
      last_sync: last_sync,
      status: cond do
        email_count == 0 and hubspot_count == 0 -> "no_data"
        email_count > 0 and hubspot_count > 0 -> "synced"
        email_count > 0 or hubspot_count > 0 -> "partial"
        true -> "unknown"
      end
    }
  end
end