Moved word for word from BACON8.md (§15) on 2026-11-19; BACON8.md keeps a short summary and links here.

## 15. Trust and safety

Built 2026-11-03 (owner's question: "how will we handle illegal content being uploaded and used on our
system?"). The plain-language answer for the owners is a shared document; this is the engineering side.
Not legal advice: the owner's lawyer has the last word on what the law asks of this site.

**What the law asks of a US site like this one (as of 2026-11):** child sexual abuse material found on it
must be reported to NCMEC's CyberTipline and preserved for a year (18 U.S.C. §2258A, as amended by the
REPORT Act); intimate images published without consent must come down within 48 hours of a valid request
(the TAKE IT DOWN Act, enforced by the FTC from 2026-05-19); copyright claims need a registered DMCA agent
(renewed every three years) to keep the safe harbour. Section 230 shields none of the federal crimes.

**How the hub handles it** (`Bacon8.Moderation`, `lib/bacon8/moderation*`):

- **Anyone can report** at `/report` (`ReportLive`): a report, a TAKE IT DOWN request (name, email, a
  signature and the sworn statement) or a DMCA notice. The thing is named by its link (`/s/<token>`,
  `/files/<id>`, an upload path) or by a plugin (`moderation_subject/2`; chat messages have a Report link).
  A honeypot field stops bots; 8 reports an hour per account or real address, 60 an hour for everyone
  signed out behind a proxy that hides addresses (§2, 2026-10-27).
- **The worst are hidden at once.** Child sexual abuse, child exploitation and intimate-image reports
  quarantine the file (`drive_files.quarantined_at`): nobody can open it, staff included. Admins get a
  notification (and a push, §16). TAKE IT DOWN requests are due in 48 hours.
- **The queue** at `/admin/moderation`, admins only: open, actioned, dismissed, blocked hashes, holds. A
  child-abuse report's content is never shown, only its facts (who, when, its hash) and the steps.
- **Actions** (each recorded with who and when): *keep evidence & remove* (a hold of the file's bytes and
  the account's details for 365 days, kept out of the drive's garbage collector; then the file is removed
  and its hash blocked), *remove*, *block its files*, *restore*, *record the NCMEC report number*, *ban the
  poster* (refused for a child-abuse report until the evidence is kept), *dismiss*, *resolve*, *note*.
- **Removed means gone everywhere**: a blocked SHA-256 is refused by the drive (`Drive.add_file/5`) and by
  every other upload (`Uploads.upload_file/4`), whoever tries it.

**The owner's steps** (none can be done in code): register with NCMEC as an electronic service provider
(reports are made in their system; the hub records the number); register a DMCA agent with the US
Copyright Office; publish terms, a privacy page and a "Report" link in the footer; decide the minimum age;
sign up for a hash-matching service (Cloudflare's CSAM Scanning Tool, free with Cloudflare in front of the
site, or Microsoft PhotoDNA) so altered copies are caught too, which exact hashes can't do; and decide
what to tell the people a report is about, beyond the law's minimum.

