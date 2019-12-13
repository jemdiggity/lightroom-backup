# lightroom-backup
Script to push/pull original photos from Lightroom to AWS S3 storage

Usually Lightroom stores the original photos into a folder structure like "year/year-month-day" while storing a "smart preview" in the Lightroom database. This utility helps you sync photos from your machine to S3. When you import photos into Lightroom, use `sync.sh push` to copy the photos to S3 and update the Lightroom database. Then you can delete the photos locally to free up local storage space. The smart previews in Lightroom mean you can still work with the photos even if they aren't stored locally.

When you need the full resolution originals back, use `sync.sh pull -d <date>` to get the original back.


# examples

## push everything in Pictures to S3
```
./sync.sh push ~/Pictures s3://lightroom
```

## pull originals for a full month
```
./sync.sh pull -d 2019-05 s3://lightroom ~/Pictures
```

## pull originals for just one day
```
./sync.sh pull -d 2019-05-10 s3://lightroom ~/Pictures
```

## first time initialization if you already have data stored on S3
```
./sync.sh init --no-previews s3://lightroom ~/Pictures
```

## restore photos from S3 Glacier for a year, month or day
Restores photos on S3 for 7 days
```
./sync.sh restore -d 2019-05 lightroom.bucket
```
