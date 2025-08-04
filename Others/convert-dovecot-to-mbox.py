#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import mailbox
import multiprocessing
from functools import partial
import time

DEFAULT_USERS_DIR = "/Volumes/Data/Library/Server/Mail/Data/mail/users"
DEFAULT_OUTPUT_DIR = os.path.expanduser("~/Desktop/MboxExport")

def parse_args():
    parser = argparse.ArgumentParser(description="Converteer Dovecot Maildirs naar mbox met gebruikersnamen uit 'users' map.")
    parser.add_argument("--users", default=DEFAULT_USERS_DIR, help="Pad naar 'users' map met symlinks/mappen naar Maildir")
    parser.add_argument("--dest", default=DEFAULT_OUTPUT_DIR, help="Pad naar exportmap voor mbox-bestanden")
    parser.add_argument("--dry-run", action="store_true", help="Toon alleen wat er zou gebeuren, voer geen conversie uit")
    parser.add_argument("--workers", type=int, default=1, help="Aantal gelijktijdige conversies (default = 1)")
    return parser.parse_args()

def count_messages(maildir_path):
    total_msgs = 0
    for sub in ("cur", "new"):
        subdir = os.path.join(maildir_path, sub)
        if os.path.isdir(subdir):
            total_msgs += len([f for f in os.listdir(subdir) if os.path.isfile(os.path.join(subdir, f))])
    return total_msgs

def choose_best_name(names):
    dotted = [n for n in names if "." in n]
    if dotted:
        return sorted(dotted)[0]
    return sorted(names)[0]

def format_duration(seconds):
    m, s = divmod(int(seconds), 60)
    return "{:02d}:{:02d}".format(m, s)

def convert_maildir(user_name, maildir_path, output_file, workers):
    start_time = time.time()
    total_msgs = count_messages(maildir_path)

    # Skip if already exists
    if os.path.exists(output_file):
        print("[{}] Bestaat al, overslaan.".format(user_name))
        return

    print("[{}] Start conversie naar {} ({} berichten)".format(user_name, output_file, total_msgs))

    if not os.path.isdir(os.path.dirname(output_file)):
        os.makedirs(os.path.dirname(output_file))

    md = mailbox.Maildir(maildir_path, factory=None)
    mb = mailbox.mbox(output_file)

    try:
        mb.lock()
    except IOError:
        print("[{}] Waarschuwing: File locking niet ondersteund, overslaan...".format(user_name))

    count = 0
    for key, msg in md.iteritems():
        mb.add(msg)
        count += 1

        if total_msgs > 0:
            percent = (count * 100) // total_msgs
        else:
            percent = 100

        if workers > 1:
            # Multi-worker: print losse regels af en toe
            if count % 100 == 0 or count == total_msgs:
                print("[{}] {}/{} berichten ({}%)".format(user_name, count, total_msgs, percent))
        else:
            # Single worker: live update op één regel
            sys.stdout.write("\r[{}] {}/{} berichten ({}%)".format(user_name, count, total_msgs, percent))
            sys.stdout.flush()

    try:
        mb.unlock()
    except Exception:
        pass

    mb.close()
    md.close()

    if workers == 1:
        sys.stdout.write("\n")

    duration = time.time() - start_time
    print("[{}] Klaar: {} berichten geconverteerd in {}".format(user_name, count, format_duration(duration)))

def main():
    args = parse_args()

    if not os.path.isdir(args.users):
        print("Users-map niet gevonden: {}".format(args.users))
        sys.exit(1)

    if not args.dry_run and not os.path.isdir(args.dest):
        os.makedirs(args.dest)

    # Verzamel unieke mailboxen met deduplicatie
    grouped = {}
    for user_name in sorted(os.listdir(args.users)):
        user_path = os.path.join(args.users, user_name)
        real_path = os.path.realpath(user_path)
        if not os.path.isdir(os.path.join(real_path, "cur")):
            continue
        total_msgs = count_messages(real_path)
        if real_path not in grouped:
            grouped[real_path] = {"names": set(), "msgs": total_msgs}
        grouped[real_path]["names"].add(user_name)

    mailbox_info = []
    for real_path, info in grouped.items():
        best_name = choose_best_name(info["names"])
        mailbox_info.append((best_name, real_path, info["msgs"]))

    # Dry-run overzicht
    if args.dry_run:
        print("\nOverzicht unieke mailboxen die worden geconverteerd:\n")
        print("{:<30} {:>10}   {}".format("Gebruiker", "Berichten", "Pad"))
        print("-" * 70)
        for name, path, msgs in sorted(mailbox_info):
            print("{:<30} {:>10}   {}".format(name, msgs, path))
        print("\nTotaal unieke mailboxen: {}".format(len(mailbox_info)))
        print("[DRY-RUN] Er worden geen bestanden geschreven.\n")
        return

    total_start = time.time()

    # Conversie uitvoeren
    if args.workers > 1:
        pool = multiprocessing.Pool(processes=args.workers)
        func = partial(_process_mailbox_worker, dest=args.dest, workers=args.workers)
        pool.map(func, mailbox_info)
        pool.close()
        pool.join()
    else:
        for name, path, msgs in sorted(mailbox_info):
            output_file = os.path.join(args.dest, name.replace(" ", "_") + ".mbox")
            convert_maildir(name, path, output_file, args.workers)

    total_duration = time.time() - total_start
    print("\nAlle mailboxen verwerkt in totaal {}".format(format_duration(total_duration)))

def _process_mailbox_worker(info, dest, workers):
    name, path, msgs = info
    output_file = os.path.join(dest, name.replace(" ", "_") + ".mbox")
    convert_maildir(name, path, output_file, workers)

if __name__ == "__main__":
    main()
