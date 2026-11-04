defmodule Bacon8.Push.WebPush do
  @moduledoc """
  Web Push, the standard way to reach a browser or an installed web app on a phone (2026-11-03,
  `Bacon8.Push`), with nothing but `:crypto`:

    * **RFC 8291** message encryption (`encrypt/4`): a fresh P-256 key pair and salt per message,
      ECDH with the subscription's `p256dh` key, HKDF with its `auth` secret, AES-128-GCM, the
      `aes128gcm` content coding of RFC 8188 (one record).
    * **RFC 8292** VAPID (`vapid_header/3`): an ES256 JSON Web Token for the push service's origin,
      signed with the site's VAPID key, so push services know who is sending.

  `generate_keys/0` makes a VAPID key pair (base64url, for `VAPID_PUBLIC_KEY` and
  `VAPID_PRIVATE_KEY`). Tested against RFC 8291's own example.
  """

  @record_size 4096

  @doc "A new VAPID key pair: `%{public: base64url (65-byte point), private: base64url (32 bytes)}`."
  def generate_keys do
    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
    %{public: b64(pub), private: b64(priv)}
  end

  @doc """
  Encrypts `plaintext` for a subscription's `p256dh` (65-byte point) and `auth` (16 bytes), all
  binaries. `opts`: `:salt` (16 bytes) and `:keys` (`{public, private}`) for tests; random otherwise.
  Returns the request body (header + ciphertext).
  """
  def encrypt(plaintext, ua_public, auth_secret, opts \\ []) when byte_size(ua_public) == 65 and byte_size(auth_secret) == 16 do
    salt = Keyword.get_lazy(opts, :salt, fn -> :crypto.strong_rand_bytes(16) end)
    {as_public, as_private} = Keyword.get_lazy(opts, :keys, fn -> :crypto.generate_key(:ecdh, :prime256v1) end)

    ecdh = :crypto.compute_key(:ecdh, ua_public, as_private, :prime256v1)
    prk_key = hmac(auth_secret, ecdh)
    ikm = hmac(prk_key, "WebPush: info" <> <<0>> <> ua_public <> as_public <> <<1>>)
    prk = hmac(salt, ikm)
    <<cek::binary-size(16), _::binary>> = hmac(prk, "Content-Encoding: aes128gcm" <> <<0, 1>>)
    <<nonce::binary-size(12), _::binary>> = hmac(prk, "Content-Encoding: nonce" <> <<0, 1>>)

    # one record: the plaintext, then the last-record delimiter (no padding)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, plaintext <> <<2>>, <<>>, true)
    salt <> <<@record_size::32, byte_size(as_public)::8>> <> as_public <> ciphertext <> tag
  end

  @doc """
  The `Authorization` header for a push to `endpoint`: `vapid t=<JWT>, k=<public key>` (RFC 8292),
  valid 12 hours. `subject` is a `mailto:` or `https:` contact for the push service.
  """
  def vapid_header(endpoint, %{public: public, private: private}, subject, now \\ System.os_time(:second)) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(endpoint)
    aud = if port in [nil, 443], do: "#{scheme}://#{host}", else: "#{scheme}://#{host}:#{port}"
    header = b64(Jason.encode!(%{typ: "JWT", alg: "ES256"}))
    claims = b64(Jason.encode!(%{aud: aud, exp: now + 12 * 3600, sub: subject}))
    signing_input = header <> "." <> claims
    der = :crypto.sign(:ecdsa, :sha256, signing_input, [unb64(private), :prime256v1])
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    "vapid t=#{signing_input}.#{b64(<<r::256, s::256>>)}, k=#{public}"
  end

  @doc "True when a JWT made by `vapid_header/4` verifies against the public key (tests, diagnostics)."
  def verify_jwt(jwt, public) do
    [h, c, sig] = String.split(jwt, ".")
    <<r::256, s::256>> = unb64(sig)
    der = :public_key.der_encode(:"ECDSA-Sig-Value", {:"ECDSA-Sig-Value", r, s})
    :crypto.verify(:ecdsa, :sha256, h <> "." <> c, der, [unb64(public), :prime256v1])
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  def b64(bin), do: Base.url_encode64(bin, padding: false)
  def unb64(s), do: Base.url_decode64!(s, padding: false)
end
