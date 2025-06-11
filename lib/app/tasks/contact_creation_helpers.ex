defmodule App.Tasks.ContactCreationHelpers do
  @moduledoc """
  Helper functions for contact creation from various data sources
  """

  def build_contact_data_from_context(context) do
    # Extract contact info from various context sources
    case context do
      %{"email_data" => email_data} ->
        build_contact_from_email(email_data)

      %{"contact_info" => contact_info} ->
        build_contact_from_info(contact_info)

      %{"from" => email, "name" => name} ->
        build_contact_from_basic_info(email, name, context)

      %{"email" => email} ->
        build_contact_from_email_only(email, context)

      _ ->
        {:error, "No valid contact information found in context"}
    end
  end

  def build_contact_from_email(email_data) do
    email = email_data["from"] || email_data[:from]

    if valid_email?(email) do
      # Parse name from email if available
      {parsed_email, name} = parse_email_with_name(email)

      contact_data = %{
                       "email" => parsed_email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "phone" => extract_phone_from_content(email_data["body"]),
        "company" => extract_company_from_email(email_data)
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  def build_contact_from_info(contact_info) do
    required_email = contact_info["email"] || contact_info[:email]

    if valid_email?(required_email) do
      contact_data = %{
                       "email" => required_email,
                       "firstname" => contact_info["firstname"] || contact_info[:firstname] ||
                         contact_info["first_name"] || contact_info[:first_name],
                       "lastname" => contact_info["lastname"] || contact_info[:lastname] ||
                         contact_info["last_name"] || contact_info[:last_name],
                       "company" => contact_info["company"] || contact_info[:company],
                       "phone" => contact_info["phone"] || contact_info[:phone]
                     }
                     |> clean_contact_data()

      {:ok, contact_data}
    else
      {:error, "Invalid or missing email address"}
    end
  end

  def build_contact_from_basic_info(email, name, context) do
    if valid_email?(email) do
      contact_data = %{
                       "email" => email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "company" => context["company"],
        "phone" => context["phone"],
        "website" => context["website"]
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  def build_contact_from_email_only(email, context) do
    if valid_email?(email) do
      # Try to infer name from email prefix
      name = email |> String.split("@") |> List.first() |> humanize_email_name()

      contact_data = %{
                       "email" => email,
                       "firstname" => extract_first_name(name),
                       "lastname" => extract_last_name(name)
                     }
                     |> add_optional_fields(%{
        "company" => infer_company_from_email(email) || context["company"],
        "phone" => context["phone"]
      })

      {:ok, contact_data}
    else
      {:error, "Invalid email address: #{email}"}
    end
  end

  # Email and name parsing functions

  def valid_email?(email) when is_binary(email) do
    email_regex = ~r/^[^\s]+@[^\s]+\.[^\s]{2,}$/
    String.match?(email, email_regex)
  end
  def valid_email?(_), do: false

  def parse_email_with_name(email_string) do
    # Handle formats like "John Smith <john@example.com>" or just "john@example.com"
    case Regex.run(~r/^(.+?)\s*<(.+?)>$/, String.trim(email_string)) do
      [_, name, email] ->
        {String.trim(email), String.trim(name)}

      nil ->
        {String.trim(email_string), nil}
    end
  end

  def extract_first_name(nil), do: nil
  def extract_first_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.split()
    |> List.first()
    |> case do
         first when byte_size(first) > 0 -> first
         _ -> nil
       end
  end

  def extract_last_name(nil), do: nil
  def extract_last_name(name) when is_binary(name) do
    parts = name |> String.trim() |> String.split()

    case length(parts) do
      0 -> nil
      1 -> nil
      _ -> Enum.drop(parts, 1) |> Enum.join(" ")
    end
  end

  def humanize_email_name(email_prefix) do
    email_prefix
    |> String.replace(~r/[._-]/, " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  def infer_company_from_email(email) do
    case String.split(email, "@") do
      [_, domain] ->
        domain
        |> String.split(".")
        |> List.first()
        |> String.replace(~r/[^a-zA-Z0-9]/, "")
        |> String.capitalize()

      _ -> nil
    end
  end

  def extract_phone_from_content(nil), do: nil
  def extract_phone_from_content(content) when is_binary(content) do
    # Look for phone numbers in various formats
    phone_patterns = [
      ~r/(\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})/,
      ~r/(\+?[0-9]{1,4}[-.\s]?)?(\(?[0-9]{2,4}\)?[-.\s]?){1,4}[0-9]{2,4}/
    ]

    Enum.find_value(phone_patterns, fn pattern ->
      case Regex.run(pattern, content) do
        [phone | _] -> String.trim(phone)
        nil -> nil
      end
    end)
  end

  def extract_company_from_email(email_data) do
    # Look for company info in email signature or domain
    content = email_data["body"] || email_data[:body] || ""

    # Check signature patterns
    signature_company = extract_company_from_signature(content)

    # Fallback to domain inference
    domain_company = case email_data["from"] do
      email when is_binary(email) -> infer_company_from_email(email)
      _ -> nil
    end

    signature_company || domain_company
  end

  def extract_company_from_signature(content) when is_binary(content) do
    # Look for common signature patterns
    patterns = [
      ~r/(?:^|\n)(.+?)\s*\n.*?(?:phone|tel|mobile|office):/i,
      ~r/(?:^|\n)(.+?)\s*\n.*?@.+?\..+/i,
      ~r/\n(.+?)\s*\n.*?(?:www\.|http)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, content) do
        [_, company] ->
          company
          |> String.trim()
          |> String.replace(~r/[^\w\s&.-]/, "")
          |> case do
               trimmed when byte_size(trimmed) > 2 and byte_size(trimmed) < 100 -> trimmed
               _ -> nil
             end

        nil -> nil
      end
    end)
  end

  def add_optional_fields(base_data, optional_fields) do
    Enum.reduce(optional_fields, base_data, fn {key, value}, acc ->
      if value && String.trim(to_string(value)) != "" do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  def clean_contact_data(contact_data) do
    contact_data
    |> Enum.reject(fn {_key, value} ->
      is_nil(value) || (is_binary(value) && String.trim(value) == "")
    end)
    |> Map.new()
  end

  # Note creation helpers

  def build_contact_note(context) do
    note_parts = []

    note_parts = if context["source_info"] do
      [context["source_info"] | note_parts]
    else
      note_parts
    end

    note_parts = if context["note"] do
      [context["note"] | note_parts]
    else
      note_parts
    end

    note_parts = if context["trigger_context"] do
      trigger_info = format_trigger_context(context["trigger_context"])
      [trigger_info | note_parts]
    else
      note_parts
    end

    note_parts = if context["email_data"] do
      email_info = format_email_context(context["email_data"])
      [email_info | note_parts]
    else
      note_parts
    end

    case note_parts do
      [] -> "Contact created automatically by AI assistant"
      parts ->
        ["Contact created automatically by AI assistant:" | Enum.reverse(parts)]
        |> Enum.join("\n\n")
    end
  end

  def format_trigger_context(trigger_context) do
    case trigger_context do
      %{"from" => from, "subject" => subject} ->
        "Triggered by email from #{from} with subject: #{subject}"

      %{"source" => source} ->
        "Triggered by: #{source}"

      _ ->
        "Triggered by automated workflow"
    end
  end

  def format_email_context(email_data) do
    "Email details:\n" <>
    "From: #{email_data["from"]}\n" <>
    "Subject: #{email_data["subject"]}\n" <>
    "Date: #{email_data["date"] || "Unknown"}"
  end

  # Knowledge base sync helper

  def sync_contact_to_knowledge_base(user, hubspot_contact, context) do
    try do
      properties = hubspot_contact["properties"] || %{}

      content = """
      HubSpot Contact: #{properties["firstname"]} #{properties["lastname"]}
      Email: #{properties["email"]}
      Company: #{properties["company"] || ""}
      Phone: #{properties["phone"] || ""}
      Created: #{DateTime.utc_now() |> DateTime.to_string()}
      Source: Automated contact creation
      Context: #{format_sync_context(context)}
      """

      case App.AI.OpenAI.create_embedding(content) do
        {:ok, embedding} ->
          attrs = %{
            user_id: user.id,
            source_type: "hubspot_contact",
            source_id: hubspot_contact["id"],
            title: "#{properties["firstname"]} #{properties["lastname"]}".trim(),
            content: content,
            metadata: Map.merge(properties, %{
              "automated_creation" => true,
              "creation_context" => context
            }),
            embedding: embedding,
            last_synced_at: DateTime.utc_now()
          }

          case App.Repo.insert(
                 App.Knowledge.KnowledgeEntry.changeset(%App.Knowledge.KnowledgeEntry{}, attrs),
                 on_conflict: :replace_all,
                 conflict_target: [:user_id, :source_type, :source_id]
               ) do
            {:ok, _entry} -> "synced_to_knowledge_base"
            {:error, _} -> "sync_failed"
          end

        {:error, _} ->
          "sync_failed_no_embedding"
      end
    rescue
      _ -> "sync_error"
    end
  end

  def format_sync_context(context) do
    case context do
      %{"instruction" => instruction} -> "Created via instruction: #{instruction}"
      %{"trigger" => trigger} -> "Triggered by: #{trigger}"
      _ -> "Automated creation"
    end
  end

  # Fallback contact creation

  def create_local_contact_fallback(user, contact_data, context) do
    try do
      # Store in local contacts table as fallback
      local_contact_attrs = %{
        user_id: user.id,
        email: contact_data["email"],
        name: "#{contact_data["firstname"]} #{contact_data["lastname"]}".trim(),
        phone: contact_data["phone"],
        company: contact_data["company"],
        metadata: %{
          "source" => "automated_creation_fallback",
          "original_context" => context,
          "hubspot_failed" => true,
          "created_at" => DateTime.utc_now() |> DateTime.to_string()
        }
      }

      case App.Repo.insert(
             App.Contacts.Contact.changeset(%App.Contacts.Contact{}, local_contact_attrs),
             on_conflict: :replace_all,
             conflict_target: [:user_id, :email]
           ) do
        {:ok, contact} ->
          %{success: true, local_contact_id: contact.id, email: contact.email}

        {:error, _changeset} ->
          %{success: false, reason: "local_storage_failed"}
      end
    rescue
      _ -> %{success: false, reason: "fallback_creation_error"}
    end
  end
end
