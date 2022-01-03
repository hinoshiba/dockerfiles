import random
import sys
#from bs4 import BeautifulSoup
import time
import json
import requests
import subprocess
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

MSG_HEADER = "[system]: "
SESSION = ""

UA_S = [
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.13; rv:62.0) Gecko/20100101 Firefox/62.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:61.0) Gecko/20100101 Firefox/61.0',
    'Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/64.0.3282.140 Safari/537.36 Edge/17.17134',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.61 Safari/537.36 Edg/94.0.992.31',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.0 Safari/605.1.15',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.82 Safari/537.36'
]
HEADER = {
    'User-Agent': UA_S[random.randrange(0, len(UA_S))]
}
proxies = {
    'http': 'socks5://localhost:9050',
    'https': 'socks5://localhost:9050'
}

def reconnect_tor():
    global HEADER
    global SESSION

    print(MSG_HEADER + "reconnecting tor...")
    subprocess.run(['service', 'tor', 'stop'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    subprocess.run(['pkill', '-f', 'tor'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    subprocess.run(['service', 'tor', 'start'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    header = {
        'User-Agent': 'curl/7.37.0'
    }
    ret = requests.get('http://ipinfo.io', headers=header, verify=False, proxies=proxies)
    gip = ret.json()
    print(MSG_HEADER + "reconnecting tor...Done: newGW: " + str(gip['ip']) + ", country: " + str(gip['country']) + ", org: " + str(gip['org']) + ", tz: "  + str(gip['timezone']))
    HEADER = {'User-Agent': UA_S[random.randrange(0, len(UA_S))]}
    print(MSG_HEADER + "init UA: " + HEADER['User-Agent'])
    SESSION = requests.Session()

if __name__ == '__main__':
    args = sys.argv

    reconnect_tor()
