#!/usr/bin/env python
import os
import sys
import argparse
import mailbox

DEFAULT_USERS_DIR = ""
DEFAULT_OUTPUT_DIR = os.path.expanduser("~/Desktop/MboxExport")

def parse_args():
    parser = argparse.ArgumentParser(description="Converteer Dovecot Maildirs naar mbox met gebruikersnamen uit 'users' map.")
    parser.add_argument("--users", default=DEFAULT_USERS_DIR, help="Pad naar 'users' map met symlinks/mappen naar Maildir")
    parser.add_argument("--dest", default=DEFAULT_OUTPUT_DIR, help="Pad naar exportmap voor mbox-bestanden")
    parser.add_argument("--dry-run", action="store_true", help="Toon alleen wat er zou gebeuren, voer geen conversie uit")
    return parser.parse_args()

def convert_maildir(maildir_path, output_file, dry_run=False):
    total_msgs = 0
    for sub in ("cur", "new"):
        subdir = os.path.join(maildir_path, sub)
        if os.path.isdir(subdir):
            total_msgs += len([f for f in os.listdir(subdir) if os.path.isfile(os.path.join(subdir, f))])

    print("Converteer:")
    print("  Bron: " + maildir_path)
    print("  Bestemming: " + output_file)
    print("  Totaal berichten gevonden: %d" % total_msgs)

    if dry_run:
        print("  [DRY-RUN] Conversie wordt niet uitgevoerd.\n")
        return

    if not os.path.isdir(os.path.dirname(output_file)):
        os.makedirs(os.path.dirname(output_file))

    md = mailbox.Maildir(maildir_path, factory=None)
    mb = mailbox.mbox(output_file)

    # Lock overslaan als het niet wordt ondersteund
    try:
        mb.lock()
    except IOError:
        print("  Waarschuwing: File locking niet ondersteund, overslaan...")

    count = 0
    for key, msg in md.iteritems():
        mb.add(msg)
        count += 1
        if total_msgs > 0:
            percent = (count * 100) / total_msgs
        else:
            percent = 100
        sys.stdout.write("\r%6d/%d berichten (%d%%)" % (count, total_msgs, percent))
        sys.stdout.flush()

    try:
        mb.unlock()
    except Exception:
        pass

    mb.close()
    md.close()
    print("\nKlaar: %d berichten geconverteerd.\n" % count)

def main():
    args = parse_args()

    if not os.path.isdir(args.users):
        print("Users-map niet gevonden:", args.users)
        sys.exit(1)

    if not args.dry_run and not os.path.isdir(args.dest):
        os.makedirs(args.dest)

    for user_name in sorted(os.listdir(args.users)):
        user_path = os.path.join(args.users, user_name)

        # Volg symlink naar echte Maildir map
        real_path = os.path.realpath(user_path)

        if not os.path.isdir(os.path.join(real_path, "cur")):
            continue

        safe_name = user_name.replace(" ", "_")
        output_file = os.path.join(args.dest, safe_name + ".mbox")

        convert_maildir(real_path, output_file, dry_run=args.dry_run)

    print("Alle mailboxen verwerkt.")
    if args.dry_run:
        print("[DRY-RUN] Er zijn geen bestanden weggeschreven.")

if __name__ == "__main__":
    main()
