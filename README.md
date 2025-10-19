Elasa Search

Convert Elesa Menu and POIs to Addok format, then search on these.


# Build
```
docker compose --profile '*' build
```

# Config
Setup configuration in `data/config.yaml`
```yaml
sources:
  cdt40:
    api: https://cdt40.carto.guide/api.teritorio/geodata/v0.1
    themes:
      - trourism
```

# Initialize data
Setup configuration in `data` and fetch data:
```
rm data/*.sjson
docker compose --profile '*' run --rm t2addok ruby update.rb https://elasa-dev.teritorio.xyz/api/0.1
```

# Run
```
docker compose up -d
```

# Data load
```
docker compose exec redis redis-cli FLUSHALL
docker compose exec addok bash -c "cat /data/*.sjson | addok batch && addok ngrams"
docker compose exec redis redis-cli BGSAVE
```
