pragma Singleton

// From https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell

Singleton {
    id: root

    function getBluetoothDeviceMaterialSymbol(systemIconName: string): string {
        if (systemIconName.includes("headset") || systemIconName.includes("headphones"))
            return "headphones";
        if (systemIconName.includes("audio"))
            return "speaker";
        if (systemIconName.includes("phone"))
            return "smartphone";
        if (systemIconName.includes("mouse"))
            return "mouse";
        if (systemIconName.includes("keyboard"))
            return "keyboard";
        return "bluetooth";
    }

    // LowPan Shells (2026-11-15): chuva em três graus (rainy_light / rainy / rainy_heavy); 302/305/308/359 são chuva
    // forte (antes saíam como granizo)
    readonly property var weatherIconMap: ({
        "113": "clear_day",
        "116": "partly_cloudy_day",
        "119": "cloud",
        "122": "cloud",
        "143": "foggy",
        "176": "rainy_light",
        "179": "rainy",
        "182": "rainy",
        "185": "rainy_light",
        "200": "thunderstorm",
        "227": "cloudy_snowing",
        "230": "weather_snowy",
        "248": "foggy",
        "260": "foggy",
        "263": "rainy_light",
        "266": "rainy_light",
        "281": "rainy_light",
        "284": "rainy_light",
        "293": "rainy_light",
        "296": "rainy_light",
        "299": "rainy",
        "302": "rainy_heavy",
        "305": "rainy_heavy",
        "308": "rainy_heavy",
        "311": "rainy_light",
        "314": "rainy",
        "317": "rainy",
        "320": "cloudy_snowing",
        "323": "cloudy_snowing",
        "326": "cloudy_snowing",
        "329": "weather_snowy",
        "332": "weather_snowy",
        "335": "weather_snowy",
        "338": "weather_snowy",
        "350": "rainy",
        "353": "rainy_light",
        "356": "rainy",
        "359": "rainy_heavy",
        "362": "rainy",
        "365": "rainy",
        "368": "cloudy_snowing",
        "371": "weather_snowy",
        "374": "rainy",
        "377": "rainy",
        "386": "thunderstorm",
        "389": "thunderstorm",
        "392": "thunderstorm",
        "395": "weather_snowy"
    })

    
    function getWeatherIcon(code, isNight) {
        const night = isNight ?? false
        const key = String(code)
        if (weatherIconMap.hasOwnProperty(key)) {
            const icon = weatherIconMap[key]
            if (night) {
                if (icon === "clear_day") return "bedtime"
                if (icon === "partly_cloudy_day") return "partly_cloudy_night"
            }
            return icon
        }
    }
}
