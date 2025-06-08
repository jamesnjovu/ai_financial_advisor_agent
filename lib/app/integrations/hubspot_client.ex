defmodule App.Integrations.HubSpotClient do
  @moduledoc """
  Enhanced HubSpot API client for CRM operations
  """

  alias App.Auth.HubSpotOAuth

  @base_url "https://api.hubapi.com"

  def get_contacts(user, opts \\ []) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]

        query_params = %{
                         limit: opts[:limit] || 100,
                         after: opts[:after]
                       }
                       |> Enum.reject(fn {_k, v} -> is_nil(v) end)
                       |> Map.new()

        url = "#{@base_url}/crm/v3/objects/contacts?#{URI.encode_query(query_params)}"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def create_contact(user, contact_data) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          properties: contact_data
        }

        url = "#{@base_url}/crm/v3/objects/contacts"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
            {:ok, Jason.decode!(body)}

          {:ok, %HTTPoison.Response{status_code: 409, body: body}} ->
            # Contact already exists, extract the existing ID and fetch the contact
            case Jason.decode(body) do
              {:ok, %{"message" => message}} ->
                case extract_contact_id_from_conflict_message(message) do
                  {:ok, existing_id} ->
                    # Fetch the existing contact
                    case get_contact(user, existing_id) do
                      {:ok, existing_contact} ->
                        # Optionally update the existing contact with new data
                        case update_contact(user, existing_id, contact_data) do
                          {:ok, updated_contact} ->
                            {:ok, %{updated_contact | "status" => "updated_existing"}}
                          {:error, _} ->
                            # If update fails, return the existing contact
                            {:ok, %{existing_contact | "status" => "existing_contact"}}
                        end
                      {:error, _} ->
                        # If we can't fetch existing, return a formatted response
                        {:ok, %{
                          "id" => existing_id,
                          "properties" => contact_data,
                          "status" => "existing_contact"
                        }}
                    end
                  {:error, _} ->
                    {:error, "Contact already exists but couldn't extract ID: #{message}"}
                end
              {:error, _} ->
                {:error, "Contact already exists but couldn't parse response: #{body}"}
            end

          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  # Helper function to extract contact ID from conflict error message
  defp extract_contact_id_from_conflict_message(message) do
    case Regex.run(~r/Existing ID: (\d+)/, message) do
      [_, id] -> {:ok, id}
      _ -> {:error, :id_not_found}
    end
  end

  def update_contact(user, contact_id, contact_data) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          properties: contact_data
        }

        url = "#{@base_url}/crm/v3/objects/contacts/#{contact_id}"

        case HTTPoison.patch(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def search_contacts(user, query) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          query: query,
          limit: 10,
          after: 0
        }

        url = "#{@base_url}/crm/v3/objects/contacts/search"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def create_note(user, contact_id, note_content) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          properties: %{
            hs_note_body: note_content,
            hs_timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
          },
          associations: [
            %{
              to: %{id: contact_id},
              types: [%{associationCategory: "HUBSPOT_DEFINED", associationTypeId: 202}]
            }
          ]
        }

        url = "#{@base_url}/crm/v3/objects/notes"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def get_contact_notes(user, contact_id) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]

        url = "#{@base_url}/crm/v4/objects/contacts/#{contact_id}/associations/notes"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def get_deals(user, opts \\ []) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]

        query_params = %{
                         limit: opts[:limit] || 100,
                         after: opts[:after]
                       }
                       |> Enum.reject(fn {_k, v} -> is_nil(v) end)
                       |> Map.new()

        url = "#{@base_url}/crm/v3/objects/deals?#{URI.encode_query(query_params)}"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def create_deal(user, deal_data) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        payload = %{
          properties: deal_data
        }

        url = "#{@base_url}/crm/v3/objects/deals"

        case HTTPoison.post(url, Jason.encode!(payload), headers) do
          {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  # Add a function to get a specific contact by ID (useful for webhooks)
  def get_contact(user, contact_id) do
    case HubSpotOAuth.get_valid_token(user) do
      {:ok, token} ->
        headers = [{"Authorization", "Bearer #{token}"}]
        url = "#{@base_url}/crm/v3/objects/contacts/#{contact_id}"

        case HTTPoison.get(url, headers) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, Jason.decode!(body)}
          {:ok, response} ->
            {:error, response}
          error ->
            error
        end
      error ->
        error
    end
  end

  def create_or_update_contact(user, contact_data) do
    email = contact_data["email"] || contact_data[:email]

    if email do
      # First, search for existing contact by email
      case search_contacts(user, email) do
        {:ok, %{"results" => [existing_contact | _]}} ->
          # Contact exists, update it
          contact_id = existing_contact["id"]
          case update_contact(user, contact_id, contact_data) do
            {:ok, updated_contact} ->
              {:ok, Map.put(updated_contact, "status", "updated_existing")}
            {:error, reason} ->
              {:error, reason}
          end

        {:ok, %{"results" => []}} ->
          # No existing contact, create new one
          create_contact(user, contact_data)

        {:error, _} ->
          # Search failed, try to create anyway (will handle 409 if needed)
          create_contact(user, contact_data)
      end
    else
      {:error, "Email is required for contact creation"}
    end
  end

  def upsert_contact(user, contact_data) do
    # Alias for create_or_update_contact for cleaner API
    create_or_update_contact(user, contact_data)
  end

end
