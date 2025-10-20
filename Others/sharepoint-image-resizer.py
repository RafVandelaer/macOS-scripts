#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SharePoint Image Resizer + Backup Tool
--------------------------------------
Doel:
- Haalt afbeeldingen uit een SharePoint/OneDrive bibliotheek via Microsoft Graph.
- Maakt lokale back-up van de originele bestanden (mapstructuur behouden).
- Verkleint afbeeldingen tot een maximale resolutie (standaard 2048px langste zijde).
- Plaatst de verkleinde versies terug in SharePoint/OneDrive.

Back-upstructuur (lokaal):
- Back-ups worden bewaard onder: <BACKUP_ROOT>/<SITE_NAME>[/<LIBRARY_NAME>]/<relatieve/structuur>/<bestandsnaam>
  (afhankelijk van BACKUP_SITE_ROOT, BACKUP_INCLUDE_LIBRARY en BACKUP_PRESERVE_TREE)

Modi:
1) Standaard:
   - Origineel in SharePoint wordt hernoemd naar *_original.
   - Verkleinde kopie wordt teruggezet als *_2k.
   - Lokaal wordt het origineel bewaard (indien BACKUP_ENABLED=True).

2) Delete originals:
   - Origineel wordt uit SharePoint verwijderd.
   - Verkleinde versie wordt teruggezet als *_2k (met suffix), NIET met de oorspronkelijke naam.
   - Lokaal blijft een back-up van het origineel (indien BACKUP_ENABLED=True).

CLI-opties:
--dry-run           Toon wat er zou gebeuren, zonder wijzigingen.
--delete-originals  Verwijder originele bestanden in SharePoint en upload de verkleinde versie als *_2k.

Belangrijke config (bovenaan script):
- BACKUP_ENABLED          True/False: maak lokale back-up.
- BACKUP_ROOT             Pad voor lokale back-up.
- BACKUP_SITE_ROOT        True/False: voeg sitenaam toe als eerste submap.
- BACKUP_INCLUDE_LIBRARY  True/False: voeg bibliotheeknaam toe als tweede submap.
- BACKUP_PRESERVE_TREE    True/False: bewaar mapstructuur onder START_FOLDER.
- BACKUP_OVERWRITE        True/False: overschrijf bestaande lokale bestanden.
- DELETE_ORIGINALS        Standaardgedrag; kan via CLI overschreven worden.

Voorbeelden:
-------------
# 1) Test-run (geen wijzigingen, alleen logs)
python3 resize_sp_images.py --dry-run

# 2) Test-run maar wél back-ups wegschrijven (voor pad- en rechtencheck)
DEBUG_DRYRUN_SAVE=True python3 resize_sp_images.py --dry-run

# 3) Productie: origineel -> *_original, verkleind -> *_2k
python3 resize_sp_images.py

# 4) Origineel verwijderen, verkleind terugplaatsen als *_2k
python3 resize_sp_images.py --delete-originals

# 5) Simuleren wat 4) zou doen
python3 resize_sp_images.py --dry-run --delete-originals
"""

import os, io, sys, json, time, logging, argparse, re, requests
from PIL import Image, ImageOps
from msal import PublicClientApplication

try:
    import colorama
    colorama.just_fix_windows_console()
except Exception:
    pass

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except Exception:
    pass

# ---------------------- CONFIG ----------------------
TENANT_ID      = "xxx"  # bijv. 'mijnbedrijf.onmicrosoft.com' of GUID
CLIENT_ID      = "yyy"  # public client app (geen secret)

SITE_NAME      = "sitename"  # bijv. 'marketing' of 'teams/site-name'
LIBRARY_NAME   = "Documenten"
START_FOLDER   = ""                  # leeg = hele bibliotheek

MAX_EDGE_PX    = 2048
RECURSIVE      = True
SKIP_IF_EXISTS = True                # alleen bij rename-flow (_2k)
QUALITY_JPEG   = 85
TIMEOUT_SEC    = 120

# Back-up lokaal
BACKUP_ENABLED          = True
BACKUP_ROOT             = "f:/"
BACKUP_SITE_ROOT        = True       # sitenaam als eerste submap
BACKUP_INCLUDE_LIBRARY  = False      # bibliotheeknaam als extra submap
BACKUP_PRESERVE_TREE    = True
BACKUP_OVERWRITE        = False

# Delete originals (default via config; kan met CLI overschreven worden)
DELETE_ORIGINALS        = True

# Dry-run gedrag
DEBUG_DRYRUN_SAVE       = True      # bij dry-run toch lokaal backup wegschrijven?

SCOPES   = ["Files.ReadWrite.All", "Sites.ReadWrite.All"]
IMG_EXT  = (".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp", ".heic")
# ----------------------------------------------------

class C:
    RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"; GREEN="\033[32m"; RED="\033[31m"
    YELLOW="\033[33m"; BLUE="\033[34m"; CYAN="\033[36m"; MAGENTA="\033[35m"; GREY="\033[90m"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

class StripAnsiFormatter(logging.Formatter):
    def format(self, record):
        return ANSI_RE.sub("", super().format(record))

def format_action(action, color): return f"{color}{action:<12}{C.RESET}"
def format_name(name, width=40):  return f"{name:<{width}.{width}}"

def human_size(num_bytes):
    for unit in ['B','KB','MB','GB']:
        if num_bytes < 1024.0: return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} TB"

def calc_saving(orig_size, new_size):
    return 0.0 if orig_size == 0 else 100.0 * (orig_size - new_size) / orig_size

def setup_logging():
    os.makedirs("logs", exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    safe_site = SITE_NAME.replace("/", "_").replace("\\", "_")
    logfile = os.path.join("logs", f"resize_{safe_site}_{ts}.log")
    logger = logging.getLogger("resizer")
    logger.setLevel(logging.INFO); logger.handlers.clear()
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.INFO); ch.setFormatter(logging.Formatter("%(message)s"))
    fh = logging.FileHandler(logfile, encoding="utf-8")
    fh.setLevel(logging.INFO); fh.setFormatter(StripAnsiFormatter("%(asctime)s | %(levelname)s | %(message)s"))
    logger.addHandler(ch); logger.addHandler(fh)
    return logger, logfile

# -------- Graph helpers --------
def get_access_token():
    app = PublicClientApplication(CLIENT_ID, authority=f"https://login.microsoftonline.com/{TENANT_ID}")
    res = app.acquire_token_interactive(SCOPES)
    if "access_token" in res: return res["access_token"]
    raise RuntimeError(f"Token ophalen mislukt: {res.get('error_description')}")

def graph_get(url, token, **kw):
    r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT_SEC, **kw); r.raise_for_status(); return r.json()

def graph_get_raw(url, token, **kw):
    r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT_SEC, allow_redirects=True, **kw)
    r.raise_for_status(); return r

def graph_patch(url, token, payload):
    r = requests.patch(url, headers={"Authorization": f"Bearer {token}", "Content-Type":"application/json"},
                       data=json.dumps(payload), timeout=TIMEOUT_SEC)
    r.raise_for_status(); return r.json()

def graph_put_raw(url, token, data):
    r = requests.put(url, headers={"Authorization": f"Bearer {token}"}, data=data, timeout=TIMEOUT_SEC)
    r.raise_for_status(); return r.json()

def graph_post(url, token, payload):
    r = requests.post(url, headers={"Authorization": f"Bearer {token}", "Content-Type":"application/json"},
                      data=json.dumps(payload), timeout=TIMEOUT_SEC)
    r.raise_for_status(); return r.json()

def graph_delete(url, token):
    r = requests.delete(url, headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT_SEC)
    if r.status_code not in (200, 204): raise RuntimeError(f"Delete faalde: {r.status_code} {r.text}")
    return True

def get_site_id(token):  return graph_get(f"https://graph.microsoft.com/v1.0/sites/root:/sites/{SITE_NAME}", token)["id"]
def get_drive_id(token, site_id):
    data = graph_get(f"https://graph.microsoft.com/v1.0/sites/{site_id}/drives", token)
    for d in data.get("value", []):
        if d.get("name") == LIBRARY_NAME: return d["id"]
    raise RuntimeError(f"Drive '{LIBRARY_NAME}' niet gevonden.")

def resolve_start_item(token, drive_id):
    if not START_FOLDER:
        return graph_get(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root", token)["id"]
    return graph_get(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{START_FOLDER}", token)["id"]

def safe_get(url, token, **kw):
    r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT_SEC, **kw)
    if r.status_code == 401:  # refresh
        token = get_access_token()
        r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=TIMEOUT_SEC, **kw)
    r.raise_for_status(); return r

def list_children(token, drive_id, item_id):
    url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}/children?$top=200"
    while url:
        data = graph_get_raw(url, token).json()
        for it in data.get("value", []): yield it
        url = data.get("@odata.nextLink")

def walk_items(token, drive_id, start_id, recursive=True):
    stack=[start_id]
    while stack:
        cur=stack.pop()
        for it in list_children(token, drive_id, cur):
            if "folder" in it and recursive: stack.append(it["id"])
            yield it

def item_parent_id(item): return item.get("parentReference", {}).get("id")
def item_path(item):      return item.get("parentReference", {}).get("path","")

def rename_item(token, drive_id, item_id, new_name):
    return graph_patch(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}", token, {"name": new_name})

def delete_item(token, drive_id, item_id):
    return graph_delete(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}", token)

def exists_in_parent(token, drive_id, parent_id, name):
    # snelle filter; zo niet toegestaan -> enumerate fallback
    escaped = name.replace("'", "''")
    base_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{parent_id}/children"
    try:
        data = safe_get(base_url, token, params={"$filter": f"name eq '{escaped}'", "$select":"id,name"}).json()
        return any(it.get("name","")==name for it in data.get("value",[]))
    except requests.HTTPError as e:
        if not e.response or e.response.status_code not in (400,401,403,501): raise
    url = f"{base_url}?$select=id,name&$top=200"
    while url:
        data = safe_get(url, token).json()
        for it in data.get("value",[]):
            if it.get("name","").lower()==name.lower(): return True
        url = data.get("@odata.nextLink")
    return False

# -------- Files / images --------
def split_name(fname): base,ext=os.path.splitext(fname); return base,ext
def plan_names(orig_name):
    base,ext = split_name(orig_name)
    return f"{base}_original{ext}", f"{base}_2k{ext}"

def download_bytes(token, drive_id, item_id, fallback_url=None):
    if fallback_url:
        try:
            r = requests.get(fallback_url, timeout=TIMEOUT_SEC)
            if r.status_code==200: return r.content
        except Exception: pass
    return graph_get_raw(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{item_id}/content", token).content

def is_image_item(item):
    if not item.get("file"): return False
    mt = item["file"].get("mimeType","").lower()
    name = item.get("name","").lower()
    return (mt.startswith("image/")) or name.endswith(IMG_EXT)

def resize_image(content, max_edge, out_ext):
    img = Image.open(io.BytesIO(content)); img = ImageOps.exif_transpose(img)
    ow,oh = img.size
    if max(ow,oh) <= max_edge: return content,(ow,oh),False
    work = img.copy(); work.thumbnail((max_edge,max_edge), Image.LANCZOS)
    nw,nh = work.size
    ext_to_fmt = {".jpg":"JPEG",".jpeg":"JPEG",".png":"PNG",".webp":"WEBP",".bmp":"BMP",".tif":"TIFF",".tiff":"TIFF",".heic":"JPEG"}
    fmt = ext_to_fmt.get(out_ext.lower(),"JPEG")
    if fmt=="JPEG" and work.mode in ("RGBA","P"): work=work.convert("RGB")
    out = io.BytesIO(); kwargs={}
    if fmt=="JPEG": kwargs=dict(quality=QUALITY_JPEG, optimize=True, progressive=True)
    work.save(out, format=fmt, **kwargs); out.seek(0)
    return out.read(), (nw,nh), True

def upload_small(token, drive_id, parent_id, new_name, content_bytes):
    return graph_put_raw(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{parent_id}:/{new_name}:/content",
                         token, content_bytes)

def upload_chunked(token, drive_id, parent_id, new_name, content_bytes, chunk=5*1024*1024):
    session = graph_post(f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{parent_id}:/{new_name}:/createUploadSession",
                         token, {"item":{"@microsoft.graph.conflictBehavior":"replace"}})
    upload_url = session.get("uploadUrl"); total=len(content_bytes); off=0
    while off<total:
        end=min(off+chunk,total); piece=content_bytes[off:end]
        r = requests.put(upload_url, headers={"Content-Length":str(len(piece)),"Content-Range":f"bytes {off}-{end-1}/{total}"},
                         data=piece, timeout=TIMEOUT_SEC)
        if r.status_code not in (200,201,202): raise RuntimeError(f"Chunk upload faalde: {r.status_code} {r.text}")
        off=end
    return True

# -------- Backup path helpers --------
def relative_dir_from_parent_path(parent_path: str) -> str:
    """
    Transformeer Graph parentReference.path naar relatieve map onder START_FOLDER.
    Voorbeeld parent_path: '/drives/<id>/root:/Foto’s/2024/Events'
    Resultaat (START_FOLDER='Foto’s'): '2024/Events'
    """
    if not parent_path: return ""
    if ":/" in parent_path: parent_path = parent_path.split(":/",1)[1]
    parent_path = parent_path.lstrip("/")
    if BACKUP_PRESERVE_TREE and START_FOLDER:
        sf = START_FOLDER.strip("/").lower(); pp = parent_path.lower()
        if pp == sf: return ""
        if pp.startswith(sf + "/"): return parent_path[len(START_FOLDER.strip("/"))+1:]
    return parent_path

def sanitize_fs(name: str) -> str:
    """Maak string veilig als mapnaam op bestandssysteem."""
    if not name: return ""
    safe = re.sub(r'[\\/:"*?<>|]+', "_", str(name))
    return safe.strip().strip(".")

def compute_backup_base() -> str:
    """
    Bepaalt de basismap voor lokale back-ups:
    <BACKUP_ROOT>/<SITE_NAME>[/<LIBRARY_NAME>]
    afhankelijk van BACKUP_SITE_ROOT en BACKUP_INCLUDE_LIBRARY.
    """
    parts = [BACKUP_ROOT]
    if BACKUP_SITE_ROOT:
        parts.append(sanitize_fs(SITE_NAME))
    if BACKUP_INCLUDE_LIBRARY:
        parts.append(sanitize_fs(LIBRARY_NAME))
    return os.path.join(*parts)

def save_local_backup(content_bytes: bytes, rel_dir: str, filename: str) -> (bool, str):
    """
    Bewaart originele bytes lokaal onder:
      compute_backup_base() / [rel_dir] / filename
    waarbij rel_dir de structuur onder START_FOLDER is (of leeg).
    """
    base = compute_backup_base()
    full_dir = os.path.join(base, rel_dir) if BACKUP_PRESERVE_TREE else base
    os.makedirs(full_dir, exist_ok=True)
    full_path = os.path.join(full_dir, filename)

    if not BACKUP_OVERWRITE and os.path.exists(full_path):
        return (False, full_path)
    with open(full_path, "wb") as f:
        f.write(content_bytes)
    return (True, full_path)

# ---------------------- MAIN ----------------------
def main():
    parser = argparse.ArgumentParser(description="Resize images in SharePoint/OneDrive in-place + lokale back-up.")
    parser.add_argument("--dry-run", action="store_true", help="Toon acties zonder wijzigingen te doen")
    parser.add_argument("--delete-originals", action="store_true",
                        help="Verwijder originele bestanden in SharePoint en upload de verkleinde versie als *_2k")
    args = parser.parse_args()

    logger, logfile = setup_logging()
    dry = bool(args.dry_run)

    # finale modus (CLI > config)
    delete_mode = bool(args.delete_originals or DELETE_ORIGINALS)

    logger.info(" SharePoint Image Resizer (2K) + Local Backup")
    logger.info(f"   • Site: {SITE_NAME} | Library: {LIBRARY_NAME} | Start: {START_FOLDER or '/'}")
    logger.info(f"   • Max edge: {MAX_EDGE_PX}px | Recursive: {RECURSIVE} | Dry-run: {dry}")
    logger.info(f"   • Backup: enabled={BACKUP_ENABLED} root='{BACKUP_ROOT}' site_root={BACKUP_SITE_ROOT} include_library={BACKUP_INCLUDE_LIBRARY} preserve_tree={BACKUP_PRESERVE_TREE} overwrite={BACKUP_OVERWRITE}")
    logger.info(f"   • Mode: {'DELETE originals → upload *_2k' if delete_mode else 'RENAME to *_original + upload *_2k'}")
    logger.info(f"   • Log: {logfile}")
    logger.info("------------------------------------------------------------")

    try:
        token    = get_access_token()
        site_id  = get_site_id(token)
        drive_id = get_drive_id(token, site_id)
        start_id = resolve_start_item(token, drive_id)
    except Exception as e:
        logger.info(f" Init mislukt: {e}"); sys.exit(1)

    total=processed=skipped=renamed=created=errors=0
    backup_saved=backup_skipped=0
    total_orig_bytes=0; total_new_bytes=0
    t0=time.time()

    try:
        for it in walk_items(token, drive_id, start_id, RECURSIVE):
            if "folder" in it or not is_image_item(it): continue

            name = it.get("name",""); base, ext = os.path.splitext(name)
            if base.endswith("_2k") or base.endswith("_original"):
                skipped += 1; continue

            total += 1
            parent_id = item_parent_id(it)

            # in rename-flow voorkomt dit dubbele _2k
            if not delete_mode and SKIP_IF_EXISTS and exists_in_parent(token, drive_id, parent_id, f"{base}_2k{ext}"):
                logger.info(f" Bestaat al: {name} → {base}_2k{ext} (overgeslagen)"); skipped += 1; continue

            # download
            try:
                content = download_bytes(token, drive_id, it["id"], it.get("@microsoft.graph.downloadUrl"))
            except Exception as e:
                logger.info(f"Download mislukt voor {name}: {e}"); errors += 1; continue

            # lokale backup
            rel_dir = relative_dir_from_parent_path(item_path(it))
            if BACKUP_ENABLED:
                if dry and not DEBUG_DRYRUN_SAVE:
                    base = compute_backup_base()
                    preview_path = os.path.join(base, rel_dir, name) if BACKUP_PRESERVE_TREE else os.path.join(base, name)
                    logger.info(f" {C.GREY}[DRY] zou lokale backup maken: {preview_path}{C.RESET}")
                else:
                    try:
                        saved, full_path = save_local_backup(content, rel_dir, name)
                        if saved: backup_saved += 1; logger.info(f" Backup lokaal: {full_path}")
                        else:     backup_skipped += 1; logger.info(f" Backup overgeslagen (bestond al): {full_path}")
                    except Exception as e:
                        errors += 1; logger.info(f" Backup mislukt ({name}): {e}")

            # resize
            try:
                resized_bytes, new_size, did_resize = resize_image(content, MAX_EDGE_PX, ext)
                orig_size=len(content); new_size_bytes=len(resized_bytes)
                total_orig_bytes += orig_size; total_new_bytes += new_size_bytes
                saving_pct=calc_saving(orig_size, new_size_bytes)
            except Exception as e:
                logger.info(f"Resizen mislukt voor {name}: {e}"); errors += 1; continue

            if not did_resize:
                logger.info(f"Geen resize nodig: {name} (<= {MAX_EDGE_PX}px)"); skipped += 1; continue

            # Dry-run: toon wat we zouden doen
            if dry:
                if delete_mode:
                    resized_name = f"{base}_2k{ext}"
                    logger.info(
                        f"{format_action('[DRY]', C.CYAN)}{format_name(resized_name)}"
                        f"{human_size(new_size_bytes):>8} / {human_size(orig_size):<8}  {saving_pct:>6.1f}%"
                        f"   {C.YELLOW}Zou ORIGINEEL verwijderen en verkleind uploaden als: {resized_name}{C.RESET}"
                    )
                else:
                    orig_new, resized_name = f"{base}_original{ext}", f"{base}_2k{ext}"
                    logger.info(
                        f"{format_action('[DRY]', C.CYAN)}{format_name(resized_name)}"
                        f"{human_size(new_size_bytes):>8} / {human_size(orig_size):<8}  {saving_pct:>6.1f}%"
                        f"   {C.YELLOW}Zou hernoemen naar {orig_new} en _2k uploaden{C.RESET}"
                    )
                processed += 1
                continue

            # Real actions
            try:
                if delete_mode:
                    # 1) verwijder origineel
                    delete_item(token, drive_id, it["id"])
                    logger.info(f" Origineel verwijderd: {name}")

                    # 2) upload verkleind met _2k suffix
                    resized_name = f"{base}_2k{ext}"
                    if len(resized_bytes) <= 3_900_000:
                        upload_small(token, drive_id, parent_id, resized_name, resized_bytes)
                    else:
                        upload_chunked(token, drive_id, parent_id, resized_name, resized_bytes)
                    created += 1
                    logger.info(f"{format_action('Done', C.GREEN)}{format_name(resized_name)}"
                                f"{human_size(new_size_bytes):>8} / {human_size(orig_size):<8}  {saving_pct:>6.1f}%"
                                f"   {C.GREY}{new_size[0]}×{new_size[1]} px{C.RESET}")
                else:
                    # 1) hernoem origineel naar *_original
                    orig_new, resized_name = f"{base}_original{ext}", f"{base}_2k{ext}"
                    rename_item(token, drive_id, it["id"], orig_new)
                    logger.info(f" Hernoemd: {name} → {orig_new}")

                    # 2) upload _2k
                    if len(resized_bytes) <= 3_900_000:
                        upload_small(token, drive_id, parent_id, resized_name, resized_bytes)
                    else:
                        upload_chunked(token, drive_id, parent_id, resized_name, resized_bytes)
                    created += 1
                    logger.info(f"{format_action('Done', C.GREEN)}{format_name(resized_name)}"
                                f"{human_size(new_size_bytes):>8} / {human_size(orig_size):<8}  {saving_pct:>6.1f}%"
                                f"   {C.GREY}{new_size[0]}×{new_size[1]} px{C.RESET}")

            except Exception as e:
                errors += 1; logger.info(f" Actie mislukt ({name}): {e}"); continue

            processed += 1

    except KeyboardInterrupt:
        logger.info(" Onderbroken door gebruiker.")

    dt = time.time() - t0
    logger.info("------------------------------------------------------------")
    logger.info("Samenvatting:")
    logger.info(f"   Gevonden (kansrijk): {total}")
    logger.info(f"   Verwerkt:            {processed}")
    logger.info(f"   Nieuw:               {created}")
    logger.info(f"   Overgeslagen:        {skipped}")
    logger.info(f"   Backups:             {backup_saved} opgeslagen, {backup_skipped} overgeslagen")
    logger.info(f"   Fouten:              {errors}")
    total_saved_bytes = max(0, total_orig_bytes - total_new_bytes)
    total_saving_pct  = (100.0 * total_saved_bytes / total_orig_bytes) if total_orig_bytes>0 else 0.0
    logger.info(f"   Totale origineel:    {human_size(total_orig_bytes)}")
    logger.info(f"   Totale nieuw:        {human_size(total_new_bytes)}")
    logger.info(f"   Totale besparing:    {human_size(total_saved_bytes)}  ({total_saving_pct:.1f}%)")
    logger.info(f"  Duur: {dt:.1f}s")
    logger.info(f"️  Logbestand: {logfile}")

if __name__ == "__main__":
    main()
