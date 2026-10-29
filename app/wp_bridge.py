import os
import requests

def check_wp_health() -> dict:
    wp_url = os.environ.get("WP_URL", "https://steamgears.eu").rstrip("/")
    wp_user = os.environ.get("WP_USER", "").strip()
    wp_pass = os.environ.get("WP_APP_PASSWORD", "").strip()
    
    result = {"site": wp_url, "reachable": False, "rest_api": False, "auth_ok": False}
    try:
        r = requests.get(f"{wp_url}/wp-json/", timeout=6)
        result["reachable"] = r.status_code < 500
        result["rest_api"] = r.status_code == 200
        if wp_user and wp_pass:
            me = requests.get(f"{wp_url}/wp-json/wp/v2/users/me", auth=(wp_user, wp_pass), timeout=6)
            result["auth_ok"] = me.status_code == 200
    except Exception as e:
        result["error"] = str(e)
    return result
