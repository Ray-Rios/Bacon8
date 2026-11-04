defmodule Mix.Tasks.Bacon8.Gen.Vapid do
  @shortdoc "Makes the key pair push notifications are signed with (Bacon8.Push)"
  @moduledoc """
  Makes a VAPID key pair for push notifications (`Bacon8.Push`) and writes it to `.env.push`
  (gitignored by `*.env.*`), ready to copy into the deployment's secrets:

      mix bacon8.gen.vapid
      mix bacon8.gen.vapid --subject mailto:admin@example.com --out somewhere/.env.push

  Prints only the public key: the private one is a secret and stays in the file (mode 0600).
  Refuses to overwrite a file that exists, because a new pair stops every device's notifications
  until its person turns them on again. /admin/notifications can make a pair too.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _rest, _bad} = OptionParser.parse(args, strict: [out: :string, subject: :string])
    out = opts[:out] || ".env.push"
    subject = opts[:subject] || "mailto:admin@example.com"

    if File.exists?(out),
      do: Mix.raise("#{out} already exists. A new pair stops every device's notifications; remove the file first if that's what you want.")

    %{public: public, private: private} = Bacon8.Push.WebPush.generate_keys()

    File.write!(out, """
    # Push notifications (Bacon8.Push). A secret: copy these into the deployment's secrets, never into git.
    VAPID_PUBLIC_KEY=#{public}
    VAPID_PRIVATE_KEY=#{private}
    VAPID_SUBJECT=#{subject}
    """)

    File.chmod!(out, 0o600)
    Mix.shell().info("Wrote #{out} (keep it secret). Its public key is\n  #{public}")
  end
end
