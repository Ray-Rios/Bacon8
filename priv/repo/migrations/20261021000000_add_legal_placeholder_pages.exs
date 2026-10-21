defmodule Bacon8.Repo.Migrations.AddLegalPlaceholderPages do
  use Ecto.Migration

  # Placeholder legal pages for the owner to edit and review with a lawyer before
  # the store takes real payments. They are created UNPUBLISHED (admins can see
  # them at /pages/<slug>; publish from /admin/pages when final). An existing page
  # with the same slug is left alone, and `down` deletes nothing: these pages
  # are content to be edited, not schema.

  @draft """
  <div style="border:1px solid #f5b301;background:rgba(245,179,1,.08);padding:12px 16px;border-radius:8px;margin-bottom:20px">
  <strong>Draft.</strong> Placeholder text, to be reviewed with a lawyer before Bacon8 takes payments.
  It is not in effect yet. Replace every [BRACKETED] item, then delete this notice and publish.
  </div>
  """

  @pages [
    {"terms", "Terms of Service", "The rules for using Bacon8, its games and its store.",
     """
     <p><em>Effective [DATE].</em></p>
     <h2>1. Who we are</h2>
     <p>[OPERATOR LEGAL NAME] (&ldquo;Bacon8&rdquo;, &ldquo;we&rdquo;) runs bacon8.net, its chat, file storage, games and store
     (together, the &ldquo;Service&rdquo;). Questions: [SUPPORT EMAIL]. By creating an account or using the Service you agree to these terms.</p>
     <h2>2. Accounts</h2>
     <ul>
     <li>You must be at least [MINIMUM AGE, e.g. 13; 16 in the EEA] to use the Service.</li>
     <li>One person per account. Keep your password and two-factor codes to yourself; you are responsible for what happens on your account.</li>
     <li>A verified email address and an active (not guest or banned) account are needed to buy anything.</li>
     </ul>
     <h2>3. Acceptable use</h2>
     <p>Do not harass, threaten or impersonate anyone; post illegal, hateful or sexual content involving minors; spam; cheat, exploit bugs
     or use unauthorised tools in our games; attack, overload or probe the Service; or upload content you have no right to share.
     [ADD OR EDIT COMMUNITY RULES.]</p>
     <h2>4. Your content</h2>
     <p>You keep ownership of what you post and upload. You give us a worldwide, non-exclusive, royalty-free licence to host, store,
     copy, display and transmit it as needed to run the Service. You are responsible for it and confirm you have the rights to share it.</p>
     <h2>5. Moderation, suspension and bans</h2>
     <p>Staff may remove content and restrict or ban accounts that break these terms. When an account is banned, its posts, comments,
     chat messages and reactions are deleted at once; its stored files are locked and deleted after 30 days unless the ban is lifted
     first; its subscriptions are cancelled and its storage tier ends. Purchases are not refunded (see <a href="/pages/refunds">Refunds &amp; Cancellations</a>).</p>
     <h2>6. Purchases</h2>
     <p>Prices are in US dollars [ADD TAX WORDING]. Card payments are handled by our payment processors (Stripe, and later PayPal) on
     their own checkout pages; we never see your full card number. Digital products are delivered to your account automatically.
     <strong>All sales are final</strong>: see <a href="/pages/refunds">Refunds &amp; Cancellations</a> and <a href="/pages/gems">Gems &amp; Promotions</a>.</p>
     <h2>7. Virtual currency and items</h2>
     <p>Gems, in-game items, access passes and other virtual goods are a limited, revocable licence to use them in the Service. They are
     not property, have no cash value and cannot be exchanged for money. Details: <a href="/pages/gems">Gems &amp; Promotions</a>.</p>
     <h2>8. Games and early access</h2>
     <p>Our games are in development. Characters, items, worlds and progress may be changed or reset, and servers may be unavailable.
     [EDIT FOR EACH GAME&rsquo;S STATUS.]</p>
     <h2>9. Our content and third-party content</h2>
     <p>The Service, its software, art, sounds and the Bacon8 name and logo belong to us or our licensors. Third-party material we use is
     listed on <a href="/pages/credits">Credits</a>. Report copyright problems as described on <a href="/pages/copyright">Copyright &amp; DMCA</a>.</p>
     <h2>10. Closing your account</h2>
     <p>You can ask us to delete your account at any time ([SUPPORT EMAIL]). If you have bought anything, the account is anonymised
     instead: your personal data is removed, and the order and ledger records are kept for accounting and tax.</p>
     <h2>11. Disclaimers and limitation of liability</h2>
     <p>[LAWYER TO DRAFT: service provided &ldquo;as is&rdquo;; limitation of liability; indemnity; consumer-law carve-outs.]</p>
     <h2>12. Governing law and disputes</h2>
     <p>[GOVERNING LAW, e.g. the State of ___, USA]. [COURTS OR ARBITRATION; CLASS-ACTION WAIVER IF ANY; CONSUMER RIGHTS THAT CANNOT BE WAIVED.]</p>
     <h2>13. Changes</h2>
     <p>We may update these terms. We will post the new version here with its effective date and, for material changes, tell signed-in users
     [HOW: email or site notice] before they take effect.</p>
     """},
    {"privacy", "Privacy Policy", "What personal data Bacon8 collects, why, and your choices.",
     """
     <p><em>Effective [DATE].</em></p>
     <h2>Who is responsible</h2>
     <p>[OPERATOR LEGAL NAME], [POSTAL ADDRESS]. Privacy questions and requests: [PRIVACY EMAIL].</p>
     <h2>What we collect</h2>
     <ul>
     <li><strong>Account:</strong> username, email address, password (stored only as a hash), role, two-factor settings, avatar and profile details you add.</li>
     <li><strong>What you create:</strong> posts, comments, chat messages, files you upload, game characters and their progress.</li>
     <li><strong>Purchases:</strong> orders, your Gem balance and history, license keys and access passes. Card details go to the payment processor (Stripe, later PayPal); we receive only references, the amount and the outcome.</li>
     <li><strong>Technical:</strong> IP addresses and request logs (for security, rate limiting and fixing faults), sign-in sessions and devices.</li>
     <li><strong>Email:</strong> the service messages we send you (verification, security alerts, receipts).</li>
     </ul>
     <h2>Cookies and local storage</h2>
     <p>We set one cookie, which keeps you signed in. The site stores a few preferences in your browser (for example, game sound on or off).
     We do not use advertising or analytics trackers. [CONFIRM BEFORE PUBLISHING.]</p>
     <h2>How we use it</h2>
     <p>To run the Service and your account; to keep it secure and stop abuse; to process and deliver purchases; to send service email;
     and to meet legal obligations. [EEA/UK: LEGAL BASES, e.g. contract, legitimate interests, legal obligation.]</p>
     <h2>Who we share it with</h2>
     <p>Our payment processors; our email delivery provider ([PROVIDER]); our hosting provider ([HOST, COUNTRY]); and authorities when the law
     requires it. We do not sell personal data.</p>
     <h2>How long we keep it</h2>
     <ul>
     <li>Account data: while your account exists.</li>
     <li>Banned accounts: posts, comments and chat are deleted at once; stored files 30 days after the ban.</li>
     <li>Deleted accounts: removed, except that purchase records are kept in anonymised form for [N] years for accounting and tax.</li>
     <li>Logs: [N] days.</li>
     </ul>
     <h2>Your rights</h2>
     <p>You can see and change most of your data in your profile, and ask us at [PRIVACY EMAIL] for a copy, a correction or deletion.
     [ADD GDPR/UK GDPR AND US STATE RIGHTS (e.g. CCPA) AS APPLICABLE, AND HOW TO COMPLAIN TO A REGULATOR.]</p>
     <h2>Children</h2>
     <p>The Service is not meant for children under [13]. If we learn that a child under that age has an account, we delete it.</p>
     <h2>Security</h2>
     <p>Passwords are hashed, connections are encrypted, payment data never touches our servers, and access to personal data is limited to staff who need it.</p>
     <h2>Changes</h2>
     <p>We will post updates here with a new effective date.</p>
     """},
    {"refunds", "Refunds & Cancellations", "All sales are final; how subscriptions, failed deliveries and disputes work.",
     """
     <h2>All sales are final</h2>
     <p>Gems, in-game items, downloads, access passes, license keys and subscriptions are not refundable, in whole or in part, except
     where the law requires it. [LAWYER: CONSUMER-LAW EXCEPTIONS, e.g. the EU/UK right of withdrawal for digital content and the
     consent and acknowledgement needed at checkout to waive it.]</p>
     <h2>Subscriptions</h2>
     <p>You can cancel at any time. Cancelling stops the next renewal; you keep access until the end of the period you have paid for.</p>
     <h2>If something does not arrive</h2>
     <p>Purchases are delivered to your account automatically, usually within seconds of payment. If one has not arrived after
     [TIME], contact [SUPPORT EMAIL] with your order number and we will deliver it.</p>
     <h2>Payment disputes and chargebacks</h2>
     <p>If you dispute a payment with your bank, everything that purchase delivered is suspended while the dispute is open, including
     Gems (which can leave your balance below zero and block spending). If the dispute is decided in our favour, it is restored; if not,
     it is removed for good. Please contact us first; most problems are quicker to fix directly.</p>
     """},
    {"copyright", "Copyright & DMCA", "How to report material that infringes your copyright.",
     """
     <p>We respect intellectual property and remove infringing material when we are told about it.</p>
     <h2>Sending a notice</h2>
     <p>Send a written notice to our designated agent with:</p>
     <ol>
     <li>your physical or electronic signature;</li>
     <li>the copyrighted work you say is infringed;</li>
     <li>the material on Bacon8 you want removed, with its URL;</li>
     <li>your name, address, telephone number and email address;</li>
     <li>a statement that you believe in good faith that the use is not authorised by the owner, its agent or the law; and</li>
     <li>a statement, under penalty of perjury, that the notice is accurate and that you are the owner or authorised to act for them.</li>
     </ol>
     <p><strong>Designated agent:</strong> [AGENT NAME], [POSTAL ADDRESS], [EMAIL, e.g. a legal@ alias].
     [REGISTER THE AGENT WITH THE U.S. COPYRIGHT OFFICE&rsquo;S DMCA DESIGNATED AGENT DIRECTORY.]</p>
     <h2>Counter-notices</h2>
     <p>If your material was removed and you believe that was a mistake, you may send a counter-notice with the details required by
     17 U.S.C. &sect; 512(g)(3). [LAWYER TO COMPLETE.]</p>
     <h2>Repeat infringers</h2>
     <p>We close the accounts of users who repeatedly infringe.</p>
     """},
    {"contact", "Contact", "How to reach the Bacon8 team.",
     """
     <ul>
     <li><strong>Help and support:</strong> [SUPPORT EMAIL]</li>
     <li><strong>Billing and orders:</strong> [BILLING EMAIL] (please include your order number)</li>
     <li><strong>Privacy requests:</strong> [PRIVACY EMAIL]</li>
     <li><strong>Copyright notices:</strong> see <a href="/pages/copyright">Copyright &amp; DMCA</a></li>
     <li><strong>Abuse and security reports:</strong> [ABUSE EMAIL]</li>
     <li><strong>Post:</strong> [POSTAL ADDRESS, if required]</li>
     </ul>
     <p>We usually reply within [N] working days.</p>
     """},
    {"credits", "Credits", "The people and projects whose work Bacon8 uses.",
     """
     <h2>Characters and animation</h2>
     <ul>
     <li>Base bodies: <em>Human Base Meshes</em> by Blender Studio (CC0).</li>
     <li>Animations: <em>Universal Animation Library</em> 1 and 2 by Quaternius (CC0), quaternius.com.</li>
     <li>Skeleton, rigging, outfits, eyes, test weapons and retargeting: made for Bacon8.</li>
     </ul>
     <h2>Sound and music</h2>
     <p>Sound effects and music were made for Bacon8.</p>
     <h2>Brand</h2>
     <p>The B8 logo is set in Inter Display by Rasmus Andersson (SIL Open Font License).</p>
     <h2>Software</h2>
     <p>Bacon8 is built with Elixir, Phoenix and Phoenix LiveView, PostgreSQL, three.js and Tailwind CSS, among other open-source projects.
     [LIST LICENCES THAT REQUIRE NOTICE, e.g. from mix.lock and assets/package.json.]</p>
     <h2>Games</h2>
     <p>[PER-GAME CREDITS, e.g. engine and plugin notices for RaysSpaceSim.]</p>
     """},
    {"gems", "Gems & Promotions", "How Gems, Bacon8's virtual currency, and promotions work.",
     """
     <h2>What Gems are</h2>
     <p>Gems are Bacon8&rsquo;s virtual currency, usable in the store and in every Bacon8 game. They are sold in packs priced in US dollars;
     100 Gems cost US$1.</p>
     <h2>What Gems are not</h2>
     <ul>
     <li>Gems are a limited licence, not property or money. They have no cash value and cannot be exchanged back for money.</li>
     <li>They cannot be sold or transferred to another account. [DECIDE: GIFTING.]</li>
     <li>They are not refundable (see <a href="/pages/refunds">Refunds &amp; Cancellations</a>).</li>
     <li>[DECIDE: Gems do not expire / expire after ___.] An account that is deleted or permanently banned loses its Gems.</li>
     </ul>
     <h2>Spending Gems</h2>
     <p>Items, passes and other products bought with Gems are delivered at once and are a licence to use them in the Service. Timed items
     and passes end when shown on the product.</p>
     <h2>Disputes</h2>
     <p>If a Gem purchase is disputed with your bank, those Gems are taken back while the dispute is open, even if that leaves your balance
     below zero. A balance below zero blocks spending until it is settled.</p>
     <h2>Promotions</h2>
     <p>We only give bonus Gems during announced promotions. Each one shows its bonus and its start and end dates on the pack.
     [LAWYER: ELIGIBILITY, ENDING EARLY, NO PURCHASE NECESSARY RULES IF ANY.]</p>
     <h2>Mistakes</h2>
     <p>We may correct obvious pricing errors and Gems or items granted by mistake.</p>
     """}
  ]

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      @pages
      |> Enum.with_index(1)
      |> Enum.map(fn {{slug, title, excerpt, html}, i} ->
        content =
          Jason.encode!(%{
            "rows" => [
              %{
                "columns" => [
                  %{
                    "width" => "full",
                    "blocks" => [
                      %{"type" => "text", "content" => @draft},
                      %{"type" => "text", "content" => html}
                    ]
                  }
                ]
              }
            ]
          })

        %{
          id: Ecto.UUID.bingenerate(),
          title: title,
          slug: slug,
          content: content,
          excerpt: excerpt,
          meta_description: excerpt,
          template_type: "default",
          is_published: false,
          category: "legal",
          order: i,
          show_share_buttons: false,
          share_platforms: [],
          share_buttons_colored: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().insert_all("pages", rows, on_conflict: :nothing, conflict_target: [:slug])
  end

  def down, do: :ok
end
