#!/usr/bin/env python3
"""
ARD Plus Downloader - Windows-compatible Python port of ard-plus-dl.sh
Requirements: pip install requests yt-dlp
"""

import argparse
import base64
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse

import requests

TOKEN_FILE = "ard-plus-token"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/119.0.0.0 Safari/537.36"
)
BASE_HEADERS = {
    "user-agent": USER_AGENT,
    "origin": "https://www.ardplus.de",
    "referer": "https://www.ardplus.de/",
}

movie_id = ""
token = ""


def login(username: str, password: str) -> str:
    """Log in and return a JWT session token."""
    encoded_username = urllib.parse.quote(username, safe="")
    encoded_password = urllib.parse.quote(password, safe="")
    payload = f"username={encoded_username}&password={encoded_password}"

    resp = requests.post(
        "https://auth.ardplus.de/auth/login"
        "?plainRedirect=true"
        "&redirectURL=https%3A%2F%2Fwww.ardplus.de%2Flogin%2Fcallback"
        "&errorRedirectURL=https%3A%2F%2Fwww.ardplus.de%2Fanmeldung%3Ferror%3Dtrue",
        headers={
            **BASE_HEADERS,
            "authority": "auth.ardplus.de",
            "content-type": "application/x-www-form-urlencoded",
        },
        data=payload,
        allow_redirects=False,
    )

    auth_header = resp.headers.get("authorization", "")
    new_token = auth_header.strip()

    if not new_token:
        print(
            f"Login not possible! Please check credentials and subscription for user {username}."
        )
        sys.exit(1)

    # Validate JWT
    parts = new_token.split(".")
    if parts:
        try:
            header_padded = parts[0] + "=" * (-len(parts[0]) % 4)
            header_decoded = base64.b64decode(header_padded).decode("utf-8", errors="replace")
            header_json = json.loads(header_decoded)
            if header_json.get("typ") != "JWT":
                raise ValueError("Not a JWT token")
        except Exception:
            print(
                f"Login not possible! Please check credentials and subscription for user {username}."
            )
            sys.exit(1)

    with open(TOKEN_FILE, "w", encoding="utf-8") as f:
        f.write(new_token)
    return new_token


def cleanup(token: str, mid: str) -> None:
    """Delete the playback session token for a content item."""
    try:
        requests.post(
            "https://token.ardplus.de/token/session/playback/delete",
            headers={
                **BASE_HEADERS,
                "authority": "token.ardplus.de",
                "content-type": "application/json",
                "cookie": f"sid={token}",
            },
            json={"contentId": mid, "contentType": "CmsMovie"},
        )
    except Exception:
        pass


def auth(token: str, mid: str) -> str:
    """Obtain authorization params for a content item. Returns the urlParam string."""
    resp = requests.post(
        "https://token.ardplus.de/token/session",
        headers={
            **BASE_HEADERS,
            "authority": "token.ardplus.de",
            "content-type": "application/json",
            "cookie": f"sid={token}",
        },
        json={
            "contentId": mid,
            "contentType": "CmsEpisode",
            "download": False,
            "appInfo": {
                "platform": "web",
                "appVersion": "1.0.0",
                "build": "web",
                "bundleIdentifier": "web",
            },
            "deviceInfo": {
                "isTouchDevice": False,
                "isTablet": False,
                "isFireOS": False,
                "appPlatform": "web",
                "isIOS": False,
                "isCastReceiver": False,
                "isSafari": False,
                "isFirefox": False,
            },
        },
    )
    return resp.json().get("authorizationParams")


def fetch_content(token: str, show_id: str) -> dict:
    """Fetch movie/series metadata from the ARD Plus GraphQL API."""
    content_url = (
        "https://data.ardplus.de/ard/graphql"
        "?extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A"
        "%2240d7cbfb79e6675c80aae2d44da2a7f74e4a4ee913b5c31b37cf9522fa64d63b%22%7D%7D"
        f"&variables=%7B%22movieId%22%3A%22{show_id}%22%2C%22externalId%22%3A%22%22%2C"
        "%22slug%22%3A%22%22%2C%22potentialMovieId%22%3A%22%22%7D"
    )
    headers = {
        **BASE_HEADERS,
        "authority": "data.ardplus.de",
        "content-type": "application/json",
        "cookie": f"sid={token}",
    }
    for attempt in range(2):
        resp = requests.get(content_url, headers=headers)
        if resp.status_code == 200:
            return resp.json()
        if attempt == 0:
            print("Couldn't get season details. Trying again!")
            time.sleep(2)
    resp.raise_for_status()


def fetch_season(token: str, season_id: str) -> dict:
    """Fetch episode list for a season."""
    season_url = (
        "https://data.ardplus.de/ard/graphql"
        "?extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A"
        "%22134d75e1e68a9599d1cdccf790839d9d71d2e7d7dca57d96f95285fcfd02b2ae%22%7D%7D"
        f"&variables=%7B%22seasonId%22%3A%22{season_id}%22%7D"
        "&operationName=EpisodesInSeasonData"
    )
    headers = {
        **BASE_HEADERS,
        "authority": "data.ardplus.de",
        "content-type": "application/json",
        "cookie": f"sid={token}",
    }
    resp = requests.get(season_url, headers=headers)
    resp.raise_for_status()
    return resp.json()


def fetch_episode_details(token: str, episode_id: str) -> dict:
    """Fetch details for a single Tatort episode."""
    episode_url = (
        "https://data.ardplus.de/ard/graphql"
        "?extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A"
        "%2240d7cbfb79e6675c80aae2d44da2a7f74e4a4ee913b5c31b37cf9522fa64d63b%22%7D%7D"
        f"&variables=%7B%22movieId%22%3A%22{episode_id}%22%2C%22externalId%22%3A%22%22%2C"
        "%22slug%22%3A%22%22%2C%22potentialMovieId%22%3A%22%22%7D"
    )
    headers = {
        **BASE_HEADERS,
        "authority": "data.ardplus.de",
        "content-type": "application/json",
        "cookie": f"sid={token}",
    }
    for attempt in range(2):
        resp = requests.get(episode_url, headers=headers)
        if resp.status_code == 200:
            return resp.json()
        if attempt == 0:
            print("Couldn't get episode details. Trying again!")
            time.sleep(2)
    resp.raise_for_status()


def sanitize(name: str) -> str:
    """Remove characters that are invalid in Windows file/directory names."""
    return re.sub(r'[<>:"/\\|?*]', "", name)


def download(download_url: str, output_path: str) -> None:
    """Invoke yt-dlp to download a video."""
    cmd = [
        "yt-dlp",
        "--quiet",
        "--progress",
        "--no-warnings",
        "--audio-multistreams",
        "-f", "bv+mergeall[vcodec=none]",
        "--sub-langs", "en.*,de.*",
        "--embed-subs",
        "--merge-output-format", "mp4",
        download_url,
        "-o", output_path,
    ]
    subprocess.run(cmd, check=False)


def download_movie(token: str, movie: dict) -> None:
    mid = movie["id"]
    name = sanitize(movie["title"])
    video_url = movie["videoSource"]["dashUrl"]
    year = movie.get("productionYear", "")
    folder = f"{name} ({year})"
    filename = os.path.join(folder, name)
    os.makedirs(folder, exist_ok=True)

    url_param = auth(token, mid)
    download_url = f"{video_url}?{url_param}"
    print(f"Lade Film {filename}...")
    download(download_url, filename)
    cleanup(token, mid)


def download_series(token: str, content_result: dict, automatic: bool, skip: int) -> None:
    series = content_result["data"]["series"]
    show_title = series["title"]
    seasons = series["seasons"]["nodes"]

    print(f"\nGewünschte Serie: {show_title}\n")

    # Print season table
    print(f"{'Option':<10} Titel")
    print(f"{'-'*6:<10} {'-'*5}")
    for s in seasons:
        print(f"{s['seasonInSeries']:<10} {s['title']}")
    print()

    if automatic:
        selected_seasons = list(range(1, len(seasons) + 1))
    else:
        raw = input("Welche Staffel möchtest du runterladen? ")
        selected_seasons = [int(x) for x in raw.split()]

    for selected_season in selected_seasons:
        season_node = seasons[selected_season - 1]
        season_id = season_node["id"]
        season_data = fetch_season(token, season_id)
        episodes = season_data["data"]["episodes"]["nodes"]
        amount = len(episodes)
        season_fmt = f"{selected_season:02d}"
        print(f"\nStaffel {selected_season} hat {amount} Folgen.")

        if skip != 1:
            print(f"Überspringe {skip - 1} Episode(n).")

        for episode in episodes[skip - 1:]:
            mid = episode["id"]
            name = sanitize(episode["title"])
            video_url = episode["videoSource"]["dashUrl"]
            ep_no = episode["episodeInSeason"]
            ep_fmt = f"{ep_no:02d}"
            show_safe = sanitize(show_title)
            folder = os.path.join(show_safe, f"Season {season_fmt}")
            os.makedirs(folder, exist_ok=True)
            filename = os.path.join(folder, f"{show_safe} S{season_fmt}E{ep_fmt} - {name}")

            url_param = auth(token, mid)
            download_url = f"{video_url}?{url_param}"
            print(f"Lade {filename}...")
            download(download_url, filename)
            cleanup(token, mid)


def download_tatort(token: str, show_path: str, ard_plus_url: str, automatic: bool, skip: int) -> None:
    tatort_city = show_path.split("-")[1] if "-" in show_path else show_path

    resp = requests.get(
        f"https://www.ardplus.de/kategorie/{show_path}",
        headers={
            **BASE_HEADERS,
            "authority": "data.ardplus.de",
            "content-type": "application/json",
            "cookie": f"sid={token}",
        },
    )
    html = resp.text

    # Extract JSON-LD structured data
    match = re.search(
        r'<script type="application/ld\+json">\s*(.*?)\s*</script>', html, re.DOTALL
    )
    if not match:
        print("Konnte keine Tatort-Episoden finden.")
        return

    tatort_data = json.loads(match.group(1))
    episodes_list = tatort_data.get("itemListElement", [])
    amount = len(episodes_list)
    city_cap = tatort_city.capitalize()
    print(f"Der Tatort {city_cap} hat {amount} Episoden.")

    if automatic:
        effective_skip = 0
    else:
        raw = input("Wie viele Episoden möchtest du überspringen? (0=alle laden) ")
        effective_skip = int(raw)
        print(f"Überspringe {effective_skip} Episode(n).")

    for episode_item in episodes_list[effective_skip:]:
        episode_url_full = episode_item.get("item", {}).get("url", "")
        ep_id_match = re.search(r"/details/([^/-]+)", episode_url_full)
        if not ep_id_match:
            continue
        episode_id = ep_id_match.group(1)

        details = fetch_episode_details(token, episode_id)
        movie_data = details["data"]["movie"]
        mid = movie_data["id"]
        name = sanitize(movie_data["title"])
        video_url = movie_data["videoSource"]["dashUrl"]
        year = movie_data.get("productionYear", "")
        custom = movie_data.get("customData") or {}
        episode_no = custom.get("episodeProductionNumber")
        team = custom.get("team")
        city = custom.get("location", "")

        filename = f"Tatort {city}"
        if team:
            filename += f" ({team})"
        if episode_no and episode_no != "null":
            filename += f" - Folge {episode_no}"
        filename += f" - {name} ({year})"
        filename = sanitize(filename)

        url_param = auth(token, mid)
        download_url = f"{video_url}?{url_param}"
        print(f"Lade {filename}...")
        download(download_url, filename)
        cleanup(token, mid)
        time.sleep(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="ARD Plus Downloader",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Usage:\n"
            "  ard-plus-dl.py [--automatic] <url> <username> <password> [skip]\n\n"
            "Examples:\n"
            "  ard-plus-dl.py https://www.ardplus.de/details/a0T0100000064DB-gegen-den-wind user pass\n"
            "  ard-plus-dl.py --automatic https://www.ardplus.de/details/... user pass"
        ),
    )
    parser.add_argument("--automatic", action="store_true", help="Download all without prompts")
    parser.add_argument("url", help="ARD Plus URL")
    parser.add_argument("username", help="ARD Plus username")
    parser.add_argument("password", help="ARD Plus password")
    parser.add_argument("skip", nargs="?", type=int, default=1, help="Number of episodes to skip (default: 1)")
    args = parser.parse_args()

    ard_plus_url = args.url
    username = args.username
    password = args.password
    skip = args.skip
    automatic = args.automatic

    # Parse show path and ID from URL
    show_path = ard_plus_url.rstrip("/").split("/")[-1]
    show_id = show_path.split("-")[0]

    current_movie_id = ""

    def handle_interrupt(sig, frame):
        print("\nCTRL+C pressed. Cleanup and exit!")
        if current_movie_id:
            cleanup(token, current_movie_id)
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_interrupt)

    # Load or fetch token
    global token
    if os.path.isfile(TOKEN_FILE):
        with open(TOKEN_FILE, "r", encoding="utf-8") as f:
            token = f.read().strip()
    else:
        token = login(username, password)

    # Validate token by testing auth
    test_movie_id = "a0S010000007GcX"
    url_param = auth(token, test_movie_id)
    if url_param is None:
        token = login(username, password)
        if os.path.isfile(TOKEN_FILE):
            with open(TOKEN_FILE, "r", encoding="utf-8") as f:
                token = f.read().strip()
        if not token:
            print(f"Login not possible! Please check credentials and subscription for user {username}.")
            sys.exit(0)
    cleanup(token, test_movie_id)

    # Fetch content metadata
    content_result = fetch_content(token, show_id)

    movie = content_result.get("data", {}).get("movie")
    tvshow = content_result.get("data", {}).get("series")

    if movie:
        download_movie(token, movie)
    elif tvshow:
        download_series(token, content_result, automatic, skip)
    elif "tatort" in ard_plus_url.lower():
        download_tatort(token, show_path, ard_plus_url, automatic, skip)
    else:
        print("invalid content")

    cleanup(token, current_movie_id)


if __name__ == "__main__":
    main()
