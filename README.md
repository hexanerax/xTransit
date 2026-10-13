# xTransit

A standalone Apple Watch app for getting around NYC by subway and bus. Search for a destination, pick a route, and see live departures and step-by-step directions on your wrist.

## Features

- Destination search with transit route results
- Live subway departures from the MTA GTFS-Realtime feeds
- Live bus times from the MTA Bus Time API
- Route directions and fares from the Google Directions API
- Map view of the route
- Rider-facing platform labels (for example "Uptown & The Bronx") from a curated lookup, `PlatformDirections.json`

## Requirements

- Xcode with the watchOS 11.6 SDK or later
- A Google Maps API key (Directions API enabled)
- An MTA Bus Time API key
- An MTA subway key is optional; the feeds work without one

## Setup

1. Clone the repo and copy the example config:

   ```bash
   cp "xTransit Watch App/Config.example.plist" "xTransit Watch App/Config.plist"
   ```

2. Fill in your keys in `Config.plist`:

   | Key | Purpose |
   | --- | --- |
   | `GoogleMapsAPIKey` | Directions and routing |
   | `MTABusTimeAPIKey` | Live bus arrivals |
   | `MTASubwayAPIKey` | Optional, sent as `x-api-key` if set |

   `Config.plist` is gitignored, so your keys stay out of version control.

3. Open `xTransit.xcodeproj` in Xcode, choose a watchOS simulator or paired watch, and run.

## Project layout

```
xTransit Watch App/
├── ContentView.swift, SearchView.swift, FilterView.swift   # search flow
├── ResultsView.swift, TransitResultsView.swift             # route results
├── RouteDetailView.swift, FullMapView.swift                # route detail and map
├── MTAService.swift                                        # subway and bus live data
├── GoogleDirectionsService.swift, PolylineDecoder.swift    # directions
├── PlatformDirectionsLookup.swift, PlatformDirections.json # platform labels
├── SubwayStops.swift, LineColors.swift                     # static transit data
└── APIConfig.swift                                         # reads Config.plist
```

## Platform direction labels

`PlatformDirections.json` is hand-curated. The `build_platform_directions.py` script in the parent project folder prints what the current MTA GTFS feed reports, so you can audit the file. It does not overwrite it.
