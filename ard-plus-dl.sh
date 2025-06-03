#!/bin/bash
FILE=ard-plus-token
# parse input parameter
ardPlusUrl=$1
username=$2
password=$3
skip=$4
movieId=''
token=''
showPath=$(echo $ardPlusUrl | rev | cut -d "/" -f1 | rev)
showId=$(echo $showPath | cut -d "-" -f1)

if [[ -z "$username" || -z "$password" ]]
then
  echo "Credentials missing! Please start the script with 3 parameters: "
  echo "./ard-plus-dl <ard-plus-url> <username> <password>"
  exit 1
fi

if [[ -z "$skip" ]]
then
    skip=1
fi

# login only if necessary
login() {
    token=$(curl -is 'https://auth.ardplus.de/auth/login?plainRedirect=true&redirectURL=https%3A%2F%2Fwww.ardplus.de%2Flogin%2Fcallback&errorRedirectURL=https%3A%2F%2Fwww.ardplus.de%2Fanmeldung%3Ferror%3Dtrue' \
    -H 'authority: auth.ardplus.de' \
    -H 'content-type: application/x-www-form-urlencoded' \
    -H 'origin: https://www.ardplus.de' \
    -H 'referer: https://www.ardplus.de/' \
    -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36' \
    --data-raw "username=${username}&password=${password}" | grep -i authorization | awk '{print $3}')
    tokenType=$(echo $token | cut -f1 -d "." | base64 -d | jq -r '.typ')
    if [[ "$tokenType" == "JWT" ]]; then
        echo $token > $FILE
    else
        echo "Login not possible! Please check credentials and subscription for user $username."
        exit 1
    fi
}

# cleanup after each episode and at the end
cleanup() {
    deleteToken=$(curl -s 'https://token.ardplus.de/token/session/playback/delete' \
    -H 'authority: token.ardplus.de' \
    -H 'content-type: application/json' \
    -H "cookie: sid=$token" \
    -H 'origin: https://www.ardplus.de' \
    -H 'referer: https://www.ardplus.de/' \
    -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36' \
    --data-raw "{\"contentId\":\"$movieId\",\"contentType\":\"CmsMovie\"}" \
    --compressed)
}

# get authorization for content
auth() {
    auth=$(curl -s 'https://token.ardplus.de/token/session' \
        -H 'authority: token.ardplus.de' \
        -H 'content-type: application/json' \
        -H "cookie: sid=$token" \
        -H 'origin: https://www.ardplus.de' \
        -H 'referer: https://www.ardplus.de/' \
        -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36' \
        --data-raw "{\"contentId\":\"$movieId\",\"contentType\":\"CmsEpisode\",\"download\":false,\"appInfo\":{\"platform\":\"web\",\"appVersion\":\"1.0.0\",\"build\":\"web\",\"bundleIdentifier\":\"web\"},\"deviceInfo\":{\"isTouchDevice\":false,\"isTablet\":false,\"isFireOS\":false,\"appPlatform\":\"web\",\"isIOS\":false,\"isCastReceiver\":false,\"isSafari\":false,\"isFirefox\":false}}" \
        --compressed)
    urlParam=$(echo ${auth} | jq -r '.authorizationParams')
    echo "$urlParam"
}

# intercept CTRL+C click to clean up before exit
term() {
    echo "CTRL+C pressed. Cleanup and exit!"
    cleanup
    exit 0
}
trap term SIGINT

# perform login
if [ -f "$FILE" ]; then
    # Using cached token
    token=$(<$FILE)
else 
    # Log in once
    login $username $password
fi

# check if token is valid
movieId="a0S010000007GcX"
urlParam=$( auth )
if [[ "$urlParam" == null ]]; then
    login $username $password
    token=$(<$FILE)
    if [[ -z "$token" ]]; then
        echo "Login not possible! Please check credentials and subscription for user $username."
        exit 0
    fi
fi
cleanup

# get requested content
contentUrl="https://data.ardplus.de/ard/graphql?extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A%2240d7cbfb79e6675c80aae2d44da2a7f74e4a4ee913b5c31b37cf9522fa64d63b%22%7D%7D&variables=%7B%22movieId%22%3A%22$showId%22%2C%22externalId%22%3A%22%22%2C%22slug%22%3A%22%22%2C%22potentialMovieId%22%3A%22%22%7D"
seasonsStatus=$(curl -s -o content-result.txt -w "%{http_code}" "${contentUrl}" \
    -H 'authority: data.ardplus.de' \
    -H 'content-type: application/json' \
    -H "cookie: sid=$token" \
    -H 'origin: https://www.ardplus.de' \
    -H 'referer: https://www.ardplus.de/' \
    -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36')
if [[ $seasonsStatus != "200" ]]; then
    #retry once
    echo "Couldn't get season details. Trying again!"
    sleep 2
    seasonsStatus=$(curl -s -o content-result.txt -w "%{http_code}" "${contentUrl}" \
    -H 'authority: data.ardplus.de' \
    -H 'content-type: application/json' \
    -H "cookie: sid=$token" \
    -H 'origin: https://www.ardplus.de' \
    -H 'referer: https://www.ardplus.de/' \
    -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36')
    contentResult=$(cat content-result.txt)
else
    contentResult=$(cat content-result.txt)
fi

# check whether content is movie or series
movie=$(echo "$contentResult" | jq '.data.movie')
tvshow=$(echo "$contentResult" | jq '.data.series')

if [[ "$movie" != null ]]; then
    movieId=$(echo "$movie" | jq -r '.id')
    name=$(echo "$movie" | jq -r '.title')
    videoUrl=$(echo "$movie" | jq -r '.videoSource.dashUrl')
    year=$(echo "$movie" | jq -r '.productionYear')
    filename="${name} (${year})"
    urlParam=$( auth )
    downloadUrl=${videoUrl}?${urlParam}
    echo "Lade Film ${filename}..."
    yt-dlp --quiet --progress --no-warnings --audio-multistreams -f "bv+mergeall[vcodec=none]" --sub-langs "en.*,de.*" --embed-subs --merge-output-format mp4 ${downloadUrl} -o "$filename"
    cleanup
elif [[ "$tvshow" != null ]]; then
    requestedShow=$(echo "$contentResult" | jq '.data.series.title')
    seasonIds=$(echo "$contentResult" | jq '[.data.series.seasons.nodes[] | { season: .seasonInSeries, seasonId: .id, title: .title }]')
    seasonOutput=$(echo "$seasonIds" | jq '[.[] | { Option: .season, Titel: .title }]' | jq -r '(.[0]|keys_unsorted|(.,map(length*"-"))),.[]|map(.)|@tsv'|column -ts $'\t')
    echo -e "\nGewünschte Serie: $requestedShow\n"
    echo -e "$seasonOutput\n"

    echo -n "Welche Staffel möchtest du runterladen? "
    read -r selectedSeason
    selectedSeasonId=$(echo "$seasonIds" | jq -r --argjson index 1 ".[$((selectedSeason - 1))].seasonId")

    seasonData=$(curl -s "https://data.ardplus.de/ard/graphql?extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A%22134d75e1e68a9599d1cdccf790839d9d71d2e7d7dca57d96f95285fcfd02b2ae%22%7D%7D&variables=%7B%22seasonId%22%3A%22$selectedSeasonId%22%7D&operationName=EpisodesInSeasonData" \
    -H 'authority: data.ardplus.de' \
    -H 'content-type: application/json' \
    -H "cookie: sid=$token" \
    -H 'origin: https://www.ardplus.de' \
    -H 'referer: https://www.ardplus.de/' \
    -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36')
    episodes=$(echo $seasonData | jq '[.data.episodes.nodes[] | { id: .id, episodeNo: .episodeInSeason, title: .title, videoUrl: .videoSource.dashUrl }]')
    amount=$(echo $episodes | jq '. | length')
    echo -e "\nStaffel $selectedSeason hat $amount Folgen."
    selectedSeasonFormatted=$(printf '%02d\n' "$selectedSeason")

    if [[ $skip != "1" ]]; then
        echo "Überspringe $skip Episode(n)."
        skip=$((skip + 1))
    fi

    # loop over all episodes and download each
    while read episode
    do
        movieId=$(echo "$episode" | jq -r '.id')
        name=$(echo "$episode" | jq -r '.title')
        videoUrl=$(echo "$episode" | jq -r '.videoUrl')
        episode=$(echo "$episode" | jq -r '.episodeNo')
        filename="S${selectedSeasonFormatted}E$(printf '%02d\n' $episode) - ${name}"
        urlParam=$( auth )
        downloadUrl=${videoUrl}?${urlParam}
        echo "Lade ${filename}..."
        yt-dlp --quiet --progress --no-warnings --audio-multistreams -f "bv+mergeall[vcodec=none]" --sub-langs "en.*,de.*" --embed-subs --merge-output-format mp4 ${downloadUrl} -o "$filename"
        cleanup
    done < <(echo "$episodes" | sed 's/\\"//g' | jq -c '.[]' | tail -n +$skip)
elif [[ "$ardPlusUrl" == *"tatort"* ]]; then
    tatortCity=$(echo $showPath | cut -d "-" -f2)
    # get all episodes per city
    tatortCityEpisodes=$(curl -s "https://data.ardplus.de/ard/graphql?operationName=CategoryDataBySlug&variables=%7B%22slug%22%3A%22tatort-$tatortCity%22%7D&extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A%221bf6e600fa91aa72bba35ee95a53677cf21b994a4c2afbcd01127259c7e88612%22%7D%7D" \
    --header 'authority: data.ardplus.de' \
    --header 'content-type: application/json' \
    --header "cookie: sid=$token" \
    --header 'origin: https://www.ardplus.de' \
    --header 'referer: https://www.ardplus.de/' \
    --header 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36')
    episodeIds=$(echo "$tatortCityEpisodes" | jq '[.data.category.content.nodes[] | { id: .contentMovie.id }]')

    amount=$(echo $episodeIds | jq '. | length')
    cityCapitalized=$(echo ${tatortCity} | awk '{$1=toupper(substr($1,0,1))substr($1,2)}1')
    echo "Der Tatort ${cityCapitalized} hat $amount Episoden."
    echo -n "Wie viele Episoden möchtest du überspringen? (0=alle laden) "
    read -r skip
    echo "Überspringe $skip Episode(n)."
    skip=$((skip + 1))

    # loop over all episodes and download each
    while read episode
    do
        movieId=$(echo "$episode" | jq -r '.id')        
        episodeUrl="https://data.ardplus.de/ard/graphql?operationName=MovieDetails&variables=%7B%22movieId%22%3A%22$movieId%22%2C%22externalId%22%3A%22%22%2C%22slug%22%3A%22%22%2C%22potentialMovieId%22%3A%22%22%7D&extensions=%7B%22persistedQuery%22%3A%7B%22version%22%3A1%2C%22sha256Hash%22%3A%226a791c24fd9716b154a3d68f9b5213eb0bf25828a5e633cdbbd2e35aa5b9a984%22%7D%7D"
        episodeDetailsStatus=$(curl -s -o current-tatort-episode.txt -w "%{http_code}" "${episodeUrl}" \
            -H 'authority: data.ardplus.de' \
            -H 'content-type: application/json' \
            -H "cookie: sid=$token" \
            -H 'origin: https://www.ardplus.de' \
            -H 'referer: https://www.ardplus.de/' \
            -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36')

        if [[ $episodeDetailsStatus != "200" ]]; then
            #retry once
            echo "Couldn't get episode details. Trying again!"
            sleep 2
            episodeDetailsStatus=$(curl -s -o current-tatort-episode.txt -w "%{http_code}" $episodeUrl \
            -H 'authority: data.ardplus.de' \
            -H 'content-type: application/json' \
            -H "cookie: sid=$token" \
            -H 'origin: https://www.ardplus.de' \
            -H 'referer: https://www.ardplus.de/' \
            -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36' \
            --compressed)
            episodeDetails=$(cat current-tatort-episode.txt)
        else
            episodeDetails=$(cat current-tatort-episode.txt)
        fi

        name=$(echo "$episodeDetails" | jq -r '.data.movie.title')
        videoUrl=$(echo "$episodeDetails" | jq -r '.data.movie.videoSource.dashUrl')
        year=$(echo "$episodeDetails" | jq -r '.data.movie.productionYear')
        customData=$(echo "$episodeDetails" | jq -r '.data.movie.customData')
        episode=$(echo "$customData" | jq -r '.episodeProductionNumber')
        team=$(echo "$customData" | jq -r '.team')
        city=$(echo "$customData" | jq -r '.location')
        filename="Tatort ${city}"
        if [[ -n "$team" ]];
        then
            filename="$filename (${team})"
        fi
        if [[ "$episode" != null ]];
        then
            filename="$filename - Folge ${episode}"
        fi
        filename="$filename - ${name} (${year})"
        urlParam=$( auth )
        downloadUrl=${videoUrl}?${urlParam}
        echo "Lade ${filename}..."
        yt-dlp --quiet --progress --no-warnings --audio-multistreams -f "bv+mergeall[vcodec=none]" --sub-langs "en.*,de.*" --embed-subs --merge-output-format mp4 ${downloadUrl} -o "$filename"
        cleanup
        sleep 1
    done < <(echo "$episodeIds" | jq -c '.[]' | tail -n +$skip )
else 
    echo "invalid content"
fi
cleanup
