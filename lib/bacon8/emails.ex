defmodule Bacon8.Emails do
  import Swoosh.Email

  defp from_email, do: System.get_env("FROM_EMAIL") || "no-reply@bacon8.net"
  defp from_name, do: System.get_env("FROM_NAME") || "Bacon8"

  def password_reset_email(user, reset_url) do
    new()
    |> to(user.email)
    |> from({from_name(), from_email()})
    |> subject("Reset your Bacon8 password")
    |> html_body(password_reset_html_body(user, reset_url))
    |> text_body(password_reset_text_body(user, reset_url))
  end

  def verification_email(user, verification_code) do
    new()
    |> to(user.email)
    |> from({from_name(), from_email()})
    |> subject("Verify your Bacon8 account")
    |> html_body(verification_html_body(user, verification_code))
    |> text_body(verification_text_body(user, verification_code))
  end

  defp password_reset_html_body(user, reset_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>Reset Your Password</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #3B82F6; color: white; padding: 20px; text-align: center; }
            .content { padding: 30px 20px; background: #f9f9f9; }
            .button { display: inline-block; background: #3B82F6; color: white; padding: 12px 24px; 
                     text-decoration: none; border-radius: 4px; margin: 20px 0; }
            .footer { padding: 20px; text-align: center; color: #666; font-size: 14px; }
            .rainbow-text {
                background: linear-gradient(45deg, #ff0000, #ff8c00, #ffd700, #00ff00, #0080ff, #8000ff, #ff0080);
                background-size: 200% 200%;
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
                animation: rainbow-animation 3s ease-in-out infinite;
            }
            @keyframes rainbow-animation {
                0% { background-position: 0% 50%; }
                50% { background-position: 100% 50%; }
                100% { background-position: 0% 50%; }
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>Bacon<span class="rainbow-text">8</span> Password Reset</h1>
            </div>
            <div class="content">
                <p>Hi #{user.name || "there"},</p>
                <p>You recently requested to reset your password for your Bacon8 account. Click the button below to reset it:</p>
                <p style="text-align: center;">
                    <a href="#{reset_url}" class="button">Reset Password</a>
                </p>
                <p><strong>This link expires in 1 hour.</strong></p>
                <p>If you did not request a password reset, please ignore this email or contact support if you have questions.</p>
                <p>Thanks,<br>The Bacon8 Team</p>
            </div>
            <div class="footer">
                <p>If you're having trouble clicking the button, copy and paste the URL below into your web browser:</p>
                <p style="word-break: break-all;">#{reset_url}</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp password_reset_text_body(user, reset_url) do
    """
    Hi #{user.name || "there"},

    You recently requested to reset your password for your Bacon8 account.

    To reset your password, visit this link:
    #{reset_url}

    This link expires in 1 hour.

    If you did not request a password reset, please ignore this email or contact support if you have questions.

    Thanks,
    The Bacon8 Team

    If you're having trouble with the link, copy and paste it into your web browser.
    """
  end

  defp verification_html_body(user, verification_code) do
    """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>Verify Your Account</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #3B82F6; color: white; padding: 20px; text-align: center; }
            .content { padding: 30px 20px; background: #f9f9f9; }
            .code { font-size: 32px; font-weight: bold; color: #3B82F6; text-align: center; 
                    background: white; padding: 20px; border-radius: 8px; margin: 20px 0; 
                    border: 2px solid #3B82F6; letter-spacing: 4px; }
            .footer { padding: 20px; text-align: center; color: #666; font-size: 14px; }
            .rainbow-text {
                background: linear-gradient(45deg, #ff0000, #ff8c00, #ffd700, #00ff00, #0080ff, #8000ff, #ff0080);
                background-size: 200% 200%;
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
                animation: rainbow-animation 3s ease-in-out infinite;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>Welcome to Bacon<span class="rainbow-text">8</span>!</h1>
            </div>
            <div class="content">
                <p>Hi #{user.name},</p>
                <p>Welcome to Bacon8! Please verify your email address by entering this code:</p>
                <div class="code">#{verification_code}</div>
                <p>This code expires in 24 hours.</p>
                <p>If you didn't create an account, please ignore this email.</p>
                <p>Thanks,<br>The Bacon8 Team</p>
            </div>
            <div class="footer">
                <p>Bacon8 - Your Gaming Platform</p>
            </div>
        </div>
    </body>
    </html>
    """
  end

  defp verification_text_body(user, verification_code) do
    """
    Hi #{user.name},

    Welcome to Bacon8! Please verify your email address by entering this code:

    #{verification_code}

    This code expires in 24 hours.

    If you didn't create an account, please ignore this email.

    Thanks,
    The Bacon8 Team
    """
  end
end