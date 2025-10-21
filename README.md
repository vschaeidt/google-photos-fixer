# How to use

## 1. Request your data 
Request your image data from [Google Takeout](https://takeout.google.com/)

## 2. Extract the images
```
for zip in downloaded/*.zip; do unzip $zip -d takeout/; done
```

## 3. Fix the metadata

```
ruby fixer.rb -s takeout/Takeout/Google\ Fotos/
```
If you want to generate missing metadata from filenames, add the option `-g`
To remove the metadata files from the image directory, add `-c`

## 4. Apply the Metadata to the images

### 4.1 Add an EXIF-friendly datetime string to each JSON

ExifTool expects DateTimeOriginal in the format "YYYY:MM:DD HH:MM:SS" (no
timezone). If you prefer to convert the epoch timestamp in the supplemental
JSON to such a string and store it back into the JSON before running exiftool,
you can use `jq` to do the conversion. The following command will update each
supplemental JSON file in-place, adding a new property `PhotoTakenTimeDate` with
the EXIF-friendly UTC datetime:

```bash
# run from the directory that contains the image directories
find takeout/Takeout/Google\ Fotos -type f -name "*.supplemental-metadata.json" \
  -print0 | xargs -0 -n1 -I{} sh -c '
    ts=$(jq -r ".photoTakenTime.timestamp // .creationTime.timestamp // empty" "{}") ;
    if [ -n "$ts" ]; then
      # strip fractional seconds, convert epoch to UTC EXIF datetime
      ts=${ts%%.*} ;
      dt=$(date -u -d "@$ts" +"%Y:%m:%d %H:%M:%S Z") ;
      jq ". + {PhotoTakenTimeDate: \"$dt\"}" "{}" > "{}".tmp && mv "{}".tmp "{}" ;
    fi'
```

### 4.2 Add an EXIF-friendly datetime string to each JSON
After this runs, each JSON that had a timestamp will contain a new top-level
string property `PhotoTakenTimeDate` (e.g. "2019:12:21 01:07:13"). You can
then tell exiftool to use that field instead of the raw timestamp:

```bash
exiftool -r -tagsfromfile "%d/%F.supplemental-metadata.json" \
  "-DateTimeOriginal<PhotoTakenTimeDate" "-CreateDate<PhotoTakenTimeDate" \
  "-AllDates<PhotoTakenTimeDate" "-TrackCreateDate<PhotoTakenTimeDate" \
  "-TrackModifyDate<PhotoTakenTimeDate" "-MediaCreateDate<PhotoTakenTimeDate" \
  "-MediaModifyDate<PhotoTakenTimeDate" \
  "-GPSAltitude<GeoDataAltitude" "-GPSLatitude<GeoDataLatitude" \
  "-GPSLatitudeRef<GeoDataLatitude" "-GPSLongitude<GeoDataLongitude" \
  "-GPSLongitudeRef<GeoDataLongitude" "-Keywords<Tags" "-Subject<Tags" \
  "-Caption-Abstract<Description" "-ImageDescription<Description" \
  -ext "*" -overwrite_original -progress takeout/Takeout/Google\ Fotos/
```

## More documentation
A more detailed description of the motivation to create this, as well as how to use it can be found on [The Blog of Rodrigo Panachi](https://blog.rpanachi.com/how-to-takeout-from-google-photos-and-fix-metadata-exif-info)