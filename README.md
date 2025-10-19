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
```
exiftool -r -d %s -tagsfromfile "%d/%F.supplemental-metadata.json" \
  "-GPSAltitude<GeoDataAltitude" "-GPSLatitude<GeoDataLatitude" \
  "-GPSLatitudeRef<GeoDataLatitude" "-GPSLongitude<GeoDataLongitude" \
  "-GPSLongitudeRef<GeoDataLongitude" "-Keywords<Tags" "-Subject<Tags" \
  "-Caption-Abstract<Description" "-ImageDescription<Description" \
  "-DateTimeOriginal<PhotoTakenTimeTimestamp" \
  "-DateCreated<PhotoTakenTimeTimestamp" \
  "-DateModified<CreationTimeTimestamp" \
  -ext "*" -overwrite_original -progress --ext json -ifd0:all= \
  takeout/Takeout/Google\ Fotos/
```

## More documentation
A more detailed description of the motivation to create this, as well as how to use it can be found on [The Blog of Rodrigo Panachi](https://blog.rpanachi.com/how-to-takeout-from-google-photos-and-fix-metadata-exif-info)