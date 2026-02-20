# AWS DynamoDB — Complete Engineering Reference Notes
> For use inside Terraform modules. Covers every feature from data modeling to streams, DAX, global tables, observability, and debugging.

---

## Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Data Modeling](#2-data-modeling)
3. [Table Configuration](#3-table-configuration)
4. [Capacity Modes](#4-capacity-modes)
5. [Indexes — LSI & GSI](#5-indexes--lsi--gsi)
6. [Read / Write Operations](#6-read--write-operations)
7. [Expressions](#7-expressions)
8. [Transactions](#8-transactions)
9. [DynamoDB Streams](#9-dynamodb-streams)
10. [Global Tables (Multi-Region)](#10-global-tables-multi-region)
11. [DynamoDB Accelerator (DAX)](#11-dynamodb-accelerator-dax)
12. [TTL (Time to Live)](#12-ttl-time-to-live)
13. [Backup & Point-in-Time Recovery](#13-backup--point-in-time-recovery)
14. [Encryption](#14-encryption)
15. [IAM & Access Control](#15-iam--access-control)
16. [VPC Endpoints](#16-vpc-endpoints)
17. [Import & Export](#17-import--export)
18. [PartiQL](#18-partiql)
19. [Observability — Metrics & Alarms](#19-observability--metrics--alarms)
20. [Observability — CloudWatch Contributor Insights](#20-observability--cloudwatch-contributor-insights)
21. [Observability — Logging](#21-observability--logging)
22. [Observability — X-Ray](#22-observability--x-ray)
23. [Debugging & Troubleshooting](#23-debugging--troubleshooting)
24. [Cost Model](#24-cost-model)
25. [Limits & Quotas](#25-limits--quotas)
26. [Best Practices](#26-best-practices)
27. [Terraform Full Resource Reference](#27-terraform-full-resource-reference)

---

## 1. Core Concepts

### What DynamoDB Is
- **Fully managed, serverless NoSQL** key-value and document database.
- Single-digit millisecond latency at any scale.
- No schema enforcement (except primary key). Each item can have different attributes.
- Data stored across **3 AZs** automatically. Strongly or eventually consistent reads.
- Horizontal scaling — no vertical scaling concept.
- Max item size: **400 KB**.

### Core Components

| Component | Description |
|---|---|
| **Table** | Collection of items. No joins between tables. |
| **Item** | A single row. Max 400 KB. |
| **Attribute** | A field on an item. |
| **Primary Key** | Uniquely identifies each item. Always required. |
| **Partition Key (PK)** | Hash key. Used to distribute data across partitions. |
| **Sort Key (SK)** | Range key. Optional. Combined with PK = composite primary key. |
| **Partition** | Internal storage node. Each partition holds up to 10 GB and handles 3,000 RCU + 1,000 WCU. |
| **RCU** | Read Capacity Unit = 1 strongly consistent read or 2 eventually consistent reads of up to 4 KB/s. |
| **WCU** | Write Capacity Unit = 1 write of up to 1 KB/s. |

### Consistency Models

| Model | Description | RCU Cost |
|---|---|---|
| **Eventually Consistent Read** | May return stale data; usually up to date within 1 second. | 0.5 RCU per 4 KB |
| **Strongly Consistent Read** | Always returns most recent committed write. | 1 RCU per 4 KB |
| **Transactional Read** | ACID across multiple items/tables. | 2 RCU per 4 KB |
| **Transactional Write** | ACID across multiple items/tables. | 2 WCU per 1 KB |

### Data Types

| Category | Types |
|---|---|
| **Scalar** | `S` (String), `N` (Number), `B` (Binary), `BOOL` (Boolean), `NULL` |
| **Document** | `M` (Map), `L` (List) |
| **Set** | `SS` (String Set), `NS` (Number Set), `BS` (Binary Set) |

- Numbers stored as strings internally — no precision loss.
- Sets: unordered, unique, no nulls. All elements same type.
- Max nesting: 32 levels deep for Maps/Lists.

---

## 2. Data Modeling

### Single-Table Design Philosophy
- DynamoDB is not relational. **Join data at write time, not read time.**
- Store multiple entity types in one table using a generic PK/SK pattern.
- Design your table around your **access patterns** — know them before you design.
- Overload PK/SK with prefixes to distinguish entity types.

### Access Pattern First Design Process
1. List all access patterns (queries your app needs).
2. Choose PK/SK to satisfy the primary access pattern.
3. Use GSIs to satisfy secondary access patterns.
4. Use composite sort keys for hierarchical queries.

### Common Patterns

#### Pattern: Simple Key-Value
```
PK=USER#123       → User item
PK=ORDER#456      → Order item
```

#### Pattern: One-to-Many (Composite Key)
```
PK=USER#123, SK=PROFILE          → User profile
PK=USER#123, SK=ORDER#2024-01-01 → Order 1
PK=USER#123, SK=ORDER#2024-02-15 → Order 2

Query: PK=USER#123, SK begins_with ORDER#  → all user orders
Query: PK=USER#123, SK between ORDER#2024-01 and ORDER#2024-12 → orders in 2024
```

#### Pattern: Many-to-Many (Adjacency List)
```
PK=USER#123,    SK=USER#123        → User entity
PK=USER#123,    SK=PROJECT#789     → User-Project relationship
PK=PROJECT#789, SK=PROJECT#789     → Project entity
PK=PROJECT#789, SK=USER#123        → Project-User relationship (inverted)

GSI: PK=SK value, SK=PK value → reverse lookup
```

#### Pattern: Composite Sort Key (hierarchy)
```
PK=COUNTRY#US, SK=STATE#CA#CITY#SF#DISTRICT#SOMA
→ Query all cities in CA: begins_with STATE#CA#CITY#
→ Query all districts in SF: begins_with STATE#CA#CITY#SF#
```

#### Pattern: Time-Series
```
PK=SENSOR#123, SK=2024-01-15T10:30:00Z → reading
PK=SENSOR#123, SK=2024-01-15T10:31:00Z → reading

Query: PK=SENSOR#123, SK between T1 and T2
```

#### Pattern: Write Sharding (hot partition avoidance)
```
# Instead of PK=STATUS#ACTIVE for all active items:
PK=STATUS#ACTIVE#0  (shard 0)
PK=STATUS#ACTIVE#1  (shard 1)
...
PK=STATUS#ACTIVE#9  (shard 9)

# Write to random shard, read from all shards in parallel (scatter-gather)
```

#### Pattern: Sparse Index
- Add an attribute only when item should appear in a GSI.
- Items without the GSI PK attribute are excluded from the index automatically.
- Example: `status=PENDING` on items awaiting processing → GSI on `status` only has pending items.

### Attribute Naming Tips
- Keep attribute names short — stored with every item, contributes to 400 KB limit.
- Use short aliases: `pk`, `sk`, `gsi1pk`, `gsi1sk` instead of long descriptive names.
- Reserve descriptive naming for non-key attributes.

---

## 3. Table Configuration

### Terraform: `aws_dynamodb_table`
```hcl
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"  # or "PROVISIONED"
  hash_key     = "pk"               # Partition key attribute name
  sort_key     = "sk"               # Sort key attribute name (optional)

  # Define only key attributes here (PK, SK, and any GSI/LSI keys)
  # Do NOT define non-key attributes — DynamoDB is schemaless for those
  attribute {
    name = "pk"
    type = "S"  # "S", "N", "B"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "gsi1pk"
    type = "S"
  }

  attribute {
    name = "gsi1sk"
    type = "S"
  }

  # Table class
  table_class = "STANDARD"  # "STANDARD" or "STANDARD_INFREQUENT_ACCESS"

  # TTL
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn  # omit for AWS-managed key
  }

  # DynamoDB Streams
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  # Options: NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES, KEYS_ONLY

  # Deletion protection
  deletion_protection_enabled = true

  # Tags
  tags = var.tags
}
```

### Table Classes

| Class | Use Case | Cost |
|---|---|---|
| `STANDARD` | Frequently accessed data | Standard pricing |
| `STANDARD_INFREQUENT_ACCESS` | Infrequently accessed (cold data, audit logs) | ~60% cheaper storage, higher read/write cost |

---

## 4. Capacity Modes

### On-Demand (PAY_PER_REQUEST)
- No capacity planning. Scales instantly.
- Pay per request. More expensive per-request than provisioned.
- Good for: unpredictable traffic, new tables, dev/test, bursty workloads.
- Limits: 40,000 RCU + 40,000 WCU per second per table (can be raised).
- Switch to provisioned after traffic patterns are understood.

```hcl
resource "aws_dynamodb_table" "on_demand" {
  billing_mode = "PAY_PER_REQUEST"
  # No read_capacity / write_capacity needed
}
```

### Provisioned
- Pre-allocate RCU and WCU. Cheaper at steady-state predictable load.
- Throttled if exceeded (unless auto-scaling is configured).
- Good for: predictable traffic, high-volume production tables.

```hcl
resource "aws_dynamodb_table" "provisioned" {
  billing_mode   = "PROVISIONED"
  read_capacity  = 100
  write_capacity = 50
}
```

### Auto-Scaling (Provisioned)
```hcl
# --- Read Auto-Scaling ---
resource "aws_appautoscaling_target" "read" {
  max_capacity       = 1000
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "read" {
  name               = "${var.table_name}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read.resource_id
  scalable_dimension = aws_appautoscaling_target.read.scalable_dimension
  service_namespace  = aws_appautoscaling_target.read.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70  # % utilization target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
  }
}

# --- Write Auto-Scaling ---
resource "aws_appautoscaling_target" "write" {
  max_capacity       = 500
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "write" {
  name               = "${var.table_name}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.write.resource_id
  scalable_dimension = aws_appautoscaling_target.write.scalable_dimension
  service_namespace  = aws_appautoscaling_target.write.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
  }
}

# --- GSI Auto-Scaling ---
resource "aws_appautoscaling_target" "gsi_read" {
  max_capacity       = 500
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.this.name}/index/${var.gsi_name}"
  scalable_dimension = "dynamodb:index:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}
```

### Switching Between Modes
- Can switch between on-demand and provisioned once per 24 hours.
- When switching to provisioned, DynamoDB sets capacity based on previous peak.

---

## 5. Indexes — LSI & GSI

### Local Secondary Index (LSI)
- Same PK as base table, different SK.
- **Must be defined at table creation** — cannot add later.
- Max 5 LSIs per table.
- Shares provisioned capacity with base table.
- Supports strongly consistent reads (unlike GSI).
- Item collection (PK + all LSI items) limited to **10 GB**.

```hcl
resource "aws_dynamodb_table" "with_lsi" {
  hash_key = "pk"
  sort_key = "sk"

  attribute { name = "pk";      type = "S" }
  attribute { name = "sk";      type = "S" }
  attribute { name = "created_at"; type = "S" }

  local_secondary_index {
    name               = "created-at-index"
    range_key          = "created_at"      # different SK than table
    projection_type    = "INCLUDE"         # "ALL", "KEYS_ONLY", "INCLUDE"
    non_key_attributes = ["status", "title"]  # only for INCLUDE
  }
}
```

### Global Secondary Index (GSI)
- Different PK and/or SK than base table.
- Can be added/deleted after table creation.
- Max 20 GSIs per table (soft limit).
- Has its own provisioned capacity (or inherits on-demand).
- Only eventually consistent reads.
- Sparse index supported (missing PK = item excluded from GSI).

```hcl
resource "aws_dynamodb_table" "with_gsi" {
  hash_key = "pk"
  sort_key = "sk"

  attribute { name = "pk";      type = "S" }
  attribute { name = "sk";      type = "S" }
  attribute { name = "gsi1pk";  type = "S" }
  attribute { name = "gsi1sk";  type = "S" }
  attribute { name = "gsi2pk";  type = "S" }

  global_secondary_index {
    name               = "gsi1"
    hash_key           = "gsi1pk"
    range_key          = "gsi1sk"
    projection_type    = "ALL"           # ALL = copies all attributes
    # For PROVISIONED tables:
    # read_capacity  = 50
    # write_capacity = 25
  }

  global_secondary_index {
    name            = "gsi2"
    hash_key        = "gsi2pk"           # no range key — key-only GSI
    projection_type = "KEYS_ONLY"        # Only PK, SK, GSI keys in index
  }
}
```

### Projection Types

| Type | What's in the Index | Use When |
|---|---|---|
| `KEYS_ONLY` | Table PK, SK + GSI PK, SK | Only need to look up keys, then GetItem |
| `INCLUDE` | Keys + listed `non_key_attributes` | Need subset of attributes |
| `ALL` | All table attributes | Need full item from index query |

### GSI Auto-Scaling (per GSI)
```hcl
resource "aws_appautoscaling_target" "gsi_write" {
  max_capacity       = 200
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.this.name}/index/gsi1"
  scalable_dimension = "dynamodb:index:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}
```

### Index Design Rules
- GSI PK should have **high cardinality** (many unique values) for even distribution.
- Avoid GSIs with low-cardinality PKs (e.g., `status=ACTIVE` with 1M items on one partition).
- Use write sharding for unavoidably hot GSI keys.
- GSI replication is **asynchronous** — small propagation lag.
- GSI capacity must keep up with base table write throughput.

---

## 6. Read / Write Operations

### Operation Summary

| Operation | Description | Consistent? | Cost |
|---|---|---|---|
| `GetItem` | Fetch single item by full PK (+SK) | Strong or eventual | 0.5-1 RCU per 4 KB |
| `PutItem` | Write/overwrite item | — | 1 WCU per 1 KB |
| `UpdateItem` | Update specific attributes | — | 1 WCU per 1 KB (whole item) |
| `DeleteItem` | Remove item | — | 1 WCU per 1 KB |
| `Query` | Fetch items by PK, optional SK filter | Strong or eventual | 0.5-1 RCU per 4 KB total |
| `Scan` | Read entire table or index | Strong or eventual | 0.5-1 RCU per 4 KB scanned |
| `BatchGetItem` | Up to 100 items across tables in one call | Strong or eventual | Per item cost |
| `BatchWriteItem` | Up to 25 PutItem/DeleteItem across tables | — | Per item cost |
| `TransactGetItems` | Up to 100 items, ACID | — | 2x RCU |
| `TransactWriteItems` | Up to 100 items, ACID | — | 2x WCU |

### GetItem
```python
response = table.get_item(
    Key={"pk": "USER#123", "sk": "PROFILE"},
    ConsistentRead=True,             # strong consistency
    ProjectionExpression="name, email, #st",
    ExpressionAttributeNames={"#st": "status"},  # alias reserved words
)
item = response.get("Item")
```

### PutItem (conditional)
```python
table.put_item(
    Item={
        "pk": "USER#123",
        "sk": "PROFILE",
        "name": "Alice",
        "email": "alice@example.com",
        "created_at": "2024-01-01T00:00:00Z",
        "version": 1,
    },
    ConditionExpression="attribute_not_exists(pk)",  # only if doesn't exist
)
```

### UpdateItem
```python
table.update_item(
    Key={"pk": "USER#123", "sk": "PROFILE"},
    UpdateExpression="SET #name = :name, version = version + :inc, updated_at = :ts REMOVE old_field",
    ConditionExpression="version = :expected_version",  # optimistic locking
    ExpressionAttributeNames={"#name": "name"},
    ExpressionAttributeValues={
        ":name": "Alice Updated",
        ":inc": 1,
        ":ts": "2024-06-01T00:00:00Z",
        ":expected_version": 1,
    },
    ReturnValues="ALL_NEW",  # NONE, ALL_OLD, UPDATED_OLD, ALL_NEW, UPDATED_NEW
)
```

### Query
```python
from boto3.dynamodb.conditions import Key, Attr

# Query all orders for a user in 2024
response = table.query(
    KeyConditionExpression=Key("pk").eq("USER#123") & Key("sk").begins_with("ORDER#2024"),
    FilterExpression=Attr("status").eq("SHIPPED"),  # filter AFTER read (costs RCU for all)
    ScanIndexForward=False,   # False = descending (newest first)
    Limit=20,
    ExclusiveStartKey=last_evaluated_key,  # pagination
    IndexName="gsi1",         # query GSI instead of base table
    ConsistentRead=False,     # False for GSI (only option), True for base table
    ProjectionExpression="pk, sk, #st, total",
    ExpressionAttributeNames={"#st": "status"},
)

items = response["Items"]
last_key = response.get("LastEvaluatedKey")  # None if last page
```

### Scan (use sparingly)
```python
# Parallel scan — divide table into segments
response = table.scan(
    Segment=0,          # current worker
    TotalSegments=4,    # total parallel workers
    FilterExpression=Attr("status").eq("ACTIVE"),
    ProjectionExpression="pk, sk",
    Limit=1000,
    ExclusiveStartKey=last_key,
)
```

### BatchGetItem
```python
response = dynamodb.batch_get_item(
    RequestItems={
        "MyTable": {
            "Keys": [
                {"pk": {"S": "USER#1"}, "sk": {"S": "PROFILE"}},
                {"pk": {"S": "USER#2"}, "sk": {"S": "PROFILE"}},
            ],
            "ConsistentRead": False,
        }
    }
)
items = response["Responses"]["MyTable"]
unprocessed = response["UnprocessedKeys"]  # retry these
```

### BatchWriteItem
```python
# Max 25 requests, 16 MB total, 400 KB per item
response = dynamodb.batch_write_item(
    RequestItems={
        "MyTable": [
            {"PutRequest": {"Item": {"pk": {"S": "USER#1"}, "sk": {"S": "PROFILE"}, "name": {"S": "Alice"}}}},
            {"DeleteRequest": {"Key": {"pk": {"S": "USER#OLD"}, "sk": {"S": "PROFILE"}}}},
        ]
    }
)
unprocessed = response["UnprocessedItems"]  # retry with backoff
```

---

## 7. Expressions

### Condition Expressions (for write operations)
```python
# Attribute exists / doesn't exist
"attribute_exists(pk)"
"attribute_not_exists(pk)"

# Attribute type check
"attribute_type(price, :type)"   # :type = "N"

# Size
"size(description) < :max"       # :max = 500

# Contains (for strings and sets)
"contains(tags, :tag)"

# Begins with
"begins_with(sk, :prefix)"

# Comparison
"version = :v AND #status IN (:s1, :s2)"

# Between
"score BETWEEN :low AND :high"
```

### Update Expressions
```python
# SET — set attribute value
"SET #name = :name, updated_at = :ts"

# SET with if_not_exists — set only if attribute doesn't exist
"SET counter = if_not_exists(counter, :zero) + :inc"

# SET list append
"SET tags = list_append(if_not_exists(tags, :empty), :new_tag)"

# REMOVE — delete an attribute or list element
"REMOVE old_attr, mylist[0]"

# ADD — add number or elements to a set
"ADD score :points, tag_set :new_tags"

# DELETE — remove elements from a set
"DELETE tag_set :remove_tags"
```

### Key Condition Expressions (Query only)
```python
# PK equality required, SK is optional
Key("pk").eq("USER#123")
Key("pk").eq("USER#123") & Key("sk").eq("PROFILE")
Key("pk").eq("USER#123") & Key("sk").begins_with("ORDER#")
Key("pk").eq("USER#123") & Key("sk").between("2024-01", "2024-12")
Key("pk").eq("USER#123") & Key("sk").lt("2024-06")
Key("pk").eq("USER#123") & Key("sk").lte("2024-06")
Key("pk").eq("USER#123") & Key("sk").gt("2024-01")
Key("pk").eq("USER#123") & Key("sk").gte("2024-01")
```

### Filter Expressions (Query + Scan — applied AFTER read)
```python
# Applied after items are read — RCU already consumed for all matched items
Attr("status").eq("ACTIVE")
Attr("age").gte(18)
Attr("name").begins_with("Al")
Attr("tags").contains("python")
Attr("score").between(50, 100)
Attr("status").is_in(["ACTIVE", "PENDING"])
~Attr("deleted").exists()                    # not exists
Attr("status").eq("ACTIVE") & Attr("age").gte(18)
Attr("status").eq("ACTIVE") | Attr("priority").eq("HIGH")
```

### Projection Expressions
```python
# Select specific attributes
ProjectionExpression="pk, sk, #name, email",
ExpressionAttributeNames={"#name": "name"}

# Nested attributes
ProjectionExpression="address.city, items[0].product_id"
```

### Reserved Words (must use ExpressionAttributeNames)
Common reserved words: `name`, `status`, `type`, `year`, `month`, `date`, `time`, `size`, `count`, `sum`, `min`, `max`, `first`, `last`, `data`, `comment`, `value`, `key`

```python
ExpressionAttributeNames={
    "#n": "name",
    "#s": "status",
    "#t": "type",
}
```

---

## 8. Transactions

### TransactWriteItems
- All-or-nothing across up to **100 items** in up to **25 tables**.
- Same region only.
- Cannot mix regular and transactional operations.
- 2x WCU cost.
- Idempotent with `ClientRequestToken` (token valid 10 minutes).

```python
dynamodb.transact_write_items(
    TransactItems=[
        {
            "Put": {
                "TableName": "Orders",
                "Item": {"pk": {"S": "ORDER#789"}, "status": {"S": "PLACED"}, "total": {"N": "99.99"}},
                "ConditionExpression": "attribute_not_exists(pk)",
            }
        },
        {
            "Update": {
                "TableName": "Inventory",
                "Key": {"pk": {"S": "PRODUCT#456"}},
                "UpdateExpression": "SET quantity = quantity - :qty",
                "ConditionExpression": "quantity >= :qty",
                "ExpressionAttributeValues": {":qty": {"N": "1"}},
            }
        },
        {
            "ConditionCheck": {
                "TableName": "Users",
                "Key": {"pk": {"S": "USER#123"}},
                "ConditionExpression": "attribute_exists(pk) AND #s = :active",
                "ExpressionAttributeNames": {"#s": "status"},
                "ExpressionAttributeValues": {":active": {"S": "ACTIVE"}},
            }
        },
    ],
    ClientRequestToken="unique-idempotency-key-123",
)
```

### TransactGetItems
```python
response = dynamodb.transact_get_items(
    TransactItems=[
        {"Get": {"TableName": "Orders",    "Key": {"pk": {"S": "ORDER#789"}}}},
        {"Get": {"TableName": "Inventory", "Key": {"pk": {"S": "PRODUCT#456"}}}},
    ]
)
items = [r["Item"] for r in response["Responses"] if "Item" in r]
```

### Transaction Conflicts
- `TransactionCanceledException` — one or more condition checks failed.
- `CancellationReasons` in the exception shows which items failed and why.
- Two concurrent transactions on the same item: one wins, one gets `TransactionConflict` error (retry).

---

## 9. DynamoDB Streams

### What Streams Provide
- Ordered sequence of item-level changes (create, update, delete).
- Records available for up to **24 hours**.
- Each stream shard: 1 MB/s write, up to 2 MB/s read.
- Typically 0-2 seconds latency.

### Stream View Types

| Type | What's Captured |
|---|---|
| `KEYS_ONLY` | Only PK and SK of modified item |
| `NEW_IMAGE` | Item after change |
| `OLD_IMAGE` | Item before change |
| `NEW_AND_OLD_IMAGES` | Both before and after (most useful, most data) |

### Enable Streams (Terraform)
```hcl
resource "aws_dynamodb_table" "this" {
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}
```

### Lambda Trigger on Stream
```hcl
resource "aws_lambda_event_source_mapping" "stream" {
  event_source_arn              = aws_dynamodb_table.this.stream_arn
  function_name                 = aws_lambda_function.processor.arn
  starting_position             = "LATEST"        # "LATEST" or "TRIM_HORIZON"
  batch_size                    = 100             # 1-10000
  maximum_batching_window_in_seconds = 5
  parallelization_factor        = 5              # 1-10 parallel processors per shard
  bisect_batch_on_function_error = true          # split batch on error
  maximum_retry_attempts        = 3
  maximum_record_age_in_seconds = 86400          # skip records older than this

  function_response_types = ["ReportBatchItemFailures"]  # partial batch response

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.stream_dlq.arn
    }
  }

  filter_criteria {
    filter {
      # Only process INSERT events on USER items
      pattern = jsonencode({
        eventName = ["INSERT"]
        dynamodb = {
          NewImage = {
            pk = { S = [{ prefix = "USER#" }] }
          }
        }
      })
    }
  }
}
```

### Lambda Stream Handler (Python)
```python
def handler(event, context):
    failed_items = []

    for record in event["Records"]:
        try:
            event_name = record["eventName"]  # INSERT, MODIFY, REMOVE
            dynamo = record["dynamodb"]

            if event_name == "INSERT":
                new_image = dynamo["NewImage"]
                process_insert(new_image)

            elif event_name == "MODIFY":
                old_image = dynamo.get("OldImage", {})
                new_image = dynamo["NewImage"]
                process_update(old_image, new_image)

            elif event_name == "REMOVE":
                old_image = dynamo["OldImage"]
                process_delete(old_image)

        except Exception as e:
            # Report failure for partial batch response
            failed_items.append({"itemIdentifier": record["dynamodb"]["SequenceNumber"]})

    return {"batchItemFailures": failed_items}
```

### Kinesis Data Streams (alternative to DynamoDB Streams)
- DynamoDB can replicate changes to a Kinesis Data Stream instead of native Streams.
- Longer retention (up to 1 year vs 24 hours).
- More consumer options (Kinesis Analytics, Firehose, etc.).

```hcl
resource "aws_dynamodb_kinesis_streaming_destination" "this" {
  table_name = aws_dynamodb_table.this.name
  stream_arn = aws_kinesis_stream.this.arn
}
```

---

## 10. Global Tables (Multi-Region)

### What Global Tables Provide
- Multi-region, multi-active (read AND write in each region).
- Replication latency: typically under 1 second between regions.
- DynamoDB handles conflict resolution (last-writer-wins based on timestamp).
- All regions must have the same table name and key schema.

### Global Tables v2 (2019 — current version)
```hcl
resource "aws_dynamodb_table" "global" {
  name             = "my-global-table"
  billing_mode     = "PAY_PER_REQUEST"  # or PROVISIONED (same in all regions)
  hash_key         = "pk"
  sort_key         = "sk"

  # Streams required for global tables
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute { name = "pk"; type = "S" }
  attribute { name = "sk"; type = "S" }

  # Define replicas
  replica {
    region_name            = "eu-west-1"
    kms_key_arn            = aws_kms_key.eu.arn   # region-specific KMS key
    point_in_time_recovery = true
    propagate_tags         = true
  }

  replica {
    region_name            = "ap-southeast-1"
    point_in_time_recovery = true
  }

  point_in_time_recovery { enabled = true }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.us.arn
  }

  tags = var.tags
}
```

### Global Table Considerations
- Each replica is a full copy — storage costs multiply by number of regions.
- Replicated WCU consumed in each region (2x+ write cost).
- Cannot use provisioned with different capacity per region.
- TTL deletions replicate to all regions.
- Streams must be `NEW_AND_OLD_IMAGES` for global tables.
- Avoid `attribute_not_exists` conditions on global tables (can conflict across regions).

---

## 11. DynamoDB Accelerator (DAX)

### What DAX Is
- In-memory cache for DynamoDB. Microsecond read latency (vs milliseconds).
- Fully managed, API-compatible (use DAX SDK instead of DynamoDB SDK).
- Write-through cache: writes go to DynamoDB and cache simultaneously.
- Not suitable for strongly consistent reads (still goes to DynamoDB).
- Not suitable for scan-heavy workloads.

### DAX Architecture
```
Application → DAX Cluster (cache)
                  ↓ (cache miss or write)
              DynamoDB Table
```

### Terraform: DAX Cluster
```hcl
resource "aws_dax_cluster" "this" {
  cluster_name       = "${var.table_name}-dax"
  iam_role_arn       = aws_iam_role.dax.arn
  node_type          = "dax.r4.large"   # dax.t3.small for dev
  replication_factor = 3                # nodes (1 primary + 2 replicas for HA)

  # Subnets (DAX must be in VPC)
  subnet_group_name  = aws_dax_subnet_group.this.name
  security_group_ids = [aws_security_group.dax.id]

  # Encryption
  server_side_encryption { enabled = true }

  # Maintenance
  maintenance_window    = "sun:05:00-sun:06:00"
  notification_topic_arn = aws_sns_topic.alerts.arn

  # Parameter group (TTL settings)
  parameter_group_name = aws_dax_parameter_group.this.name

  tags = var.tags
}

resource "aws_dax_subnet_group" "this" {
  name       = "${var.table_name}-dax-subnet"
  subnet_ids = var.private_subnet_ids
}

resource "aws_dax_parameter_group" "this" {
  name = "${var.table_name}-dax-params"

  parameters {
    name  = "query-ttl-millis"
    value = "300000"  # 5 minutes query cache TTL
  }

  parameters {
    name  = "record-ttl-millis"
    value = "600000"  # 10 minutes item cache TTL
  }
}

resource "aws_security_group" "dax" {
  name   = "${var.table_name}-dax-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = 8111   # DAX port (unencrypted)
    to_port         = 8111
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  ingress {
    from_port       = 9111   # DAX port (TLS/encrypted)
    to_port         = 9111
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }
}

resource "aws_iam_role" "dax" {
  name = "${var.table_name}-dax-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dax.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dax" {
  role = aws_iam_role.dax.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:*"]
      Resource = [aws_dynamodb_table.this.arn, "${aws_dynamodb_table.this.arn}/index/*"]
    }]
  })
}
```

### DAX Node Types

| Type | Memory | vCPU |
|---|---|---|
| `dax.t3.small` | 2 GB | 2 |
| `dax.t3.medium` | 4 GB | 2 |
| `dax.r4.large` | 15 GB | 2 |
| `dax.r4.xlarge` | 30 GB | 4 |
| `dax.r4.2xlarge` | 60 GB | 8 |
| `dax.r4.4xlarge` | 122 GB | 16 |
| `dax.r4.8xlarge` | 244 GB | 32 |

---

## 12. TTL (Time to Live)

### How TTL Works
- Add a Number attribute containing a **Unix epoch timestamp (seconds)**.
- DynamoDB automatically deletes items after that timestamp.
- Deletion happens within 48 hours of expiry (typically within minutes).
- TTL deletes do NOT consume WCU.
- TTL deletes appear in DynamoDB Streams as `REMOVE` events with `userIdentity.type = "Service"`.
- TTL deletes are NOT replicated to Global Table replicas (each replica handles its own TTL).

```hcl
resource "aws_dynamodb_table" "this" {
  ttl {
    attribute_name = "expires_at"  # must be Number type
    enabled        = true
  }
}
```

### Setting TTL in Code
```python
import time

# Expire in 7 days
expires_at = int(time.time()) + (7 * 24 * 60 * 60)

table.put_item(Item={
    "pk": "SESSION#abc123",
    "sk": "SESSION",
    "user_id": "USER#123",
    "expires_at": expires_at,  # TTL attribute
})
```

### Filter TTL-deleted records from Stream
```python
for record in event["Records"]:
    # Skip TTL-driven deletes
    if (record.get("userIdentity", {}).get("type") == "Service" and
        record.get("userIdentity", {}).get("principalId") == "dynamodb.amazonaws.com"):
        continue
```

---

## 13. Backup & Point-in-Time Recovery

### PITR (Point-in-Time Recovery)
- Continuous backups. Restore to any second in the past **35 days**.
- Restores to a **new table** (cannot restore in-place).
- No performance impact on production table.

```hcl
resource "aws_dynamodb_table" "this" {
  point_in_time_recovery {
    enabled = true
  }
}
```

### Restore from PITR (AWS CLI)
```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name my-table \
  --target-table-name my-table-restored \
  --restore-date-time "2024-06-01T12:00:00Z" \
  --use-latest-restorable-time  # OR use specific restore-date-time
```

### On-Demand Backups
- Manual backups. Retained until explicitly deleted. No expiry.
- Useful for: before major migrations, compliance snapshots.

```hcl
resource "aws_dynamodb_table_item" "this" {} # No native Terraform for on-demand backup
# Use aws_backup instead:

resource "aws_backup_plan" "dynamodb" {
  name = "${var.table_name}-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 2 * * ? *)"  # 2 AM UTC daily

    lifecycle {
      delete_after = 30  # days
    }

    recovery_point_tags = var.tags
  }
}

resource "aws_backup_selection" "dynamodb" {
  name         = "${var.table_name}-backup-selection"
  plan_id      = aws_backup_plan.dynamodb.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [aws_dynamodb_table.this.arn]
}

resource "aws_backup_vault" "this" {
  name        = "${var.table_name}-backup-vault"
  kms_key_arn = aws_kms_key.backup.arn
  tags        = var.tags
}
```

---

## 14. Encryption

### Encryption Options

| Type | Description | Key Management |
|---|---|---|
| `AWS_OWNED_KEY` (default) | AWS-owned CMK shared across accounts | AWS manages; free |
| `AWS_MANAGED_KEY` | AWS-managed key in your account (`aws/dynamodb`) | AWS manages; KMS charges |
| `CUSTOMER_MANAGED_KEY` | Your KMS CMK | You manage; full control |

```hcl
# Customer-managed KMS key
resource "aws_kms_key" "dynamodb" {
  description             = "DynamoDB table encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM policies"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow DynamoDB"
        Effect = "Allow"
        Principal = { Service = "dynamodb.amazonaws.com" }
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${var.table_name}"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_dynamodb_table" "this" {
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }
}
```

---

## 15. IAM & Access Control

### Execution Role Policies
```hcl
data "aws_iam_policy_document" "dynamodb" {
  # Full CRUD on table
  statement {
    effect  = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:ConditionCheckItem",
    ]
    resources = [
      aws_dynamodb_table.this.arn,
      "${aws_dynamodb_table.this.arn}/index/*",  # required for GSI access
    ]
  }

  # Streams access (for Lambda processor)
  statement {
    effect  = "Allow"
    actions = [
      "dynamodb:GetShardIterator",
      "dynamodb:GetRecords",
      "dynamodb:DescribeStream",
      "dynamodb:ListStreams",
    ]
    resources = ["${aws_dynamodb_table.this.arn}/stream/*"]
  }

  # If using CMK encryption
  statement {
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.dynamodb.arn]
  }
}
```

### Fine-Grained Access Control (item-level)
```hcl
# Restrict access to items where pk matches user's Cognito sub
data "aws_iam_policy_document" "fine_grained" {
  statement {
    effect  = "Allow"
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.this.arn]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "dynamodb:LeadingKeys"
      values   = ["$${cognito-identity.amazonaws.com:sub}"]  # IAM policy variable
    }

    condition {
      test     = "StringEquals"
      variable = "dynamodb:Select"
      values   = ["SPECIFIC_ATTRIBUTES"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "dynamodb:Attributes"
      values   = ["pk", "sk", "name", "email"]  # allowed attributes
    }
  }
}
```

### Resource-Based Policy (cross-account access)
```hcl
resource "aws_dynamodb_resource_policy" "this" {
  resource_arn = aws_dynamodb_table.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CrossAccountRead"
      Effect = "Allow"
      Principal = { AWS = "arn:aws:iam::123456789012:root" }
      Action   = ["dynamodb:GetItem", "dynamodb:Query"]
      Resource = [
        aws_dynamodb_table.this.arn,
        "${aws_dynamodb_table.this.arn}/index/*"
      ]
    }]
  })
}
```

---

## 16. VPC Endpoints

```hcl
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"  # DynamoDB uses Gateway endpoint (free)

  route_table_ids = var.private_route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "dynamodb:*"
      Resource  = "*"
      Condition = {
        StringEquals = {
          "aws:sourceVpc" = var.vpc_id
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "dynamodb-endpoint" })
}
```

> DynamoDB VPC endpoints are **Gateway type** (not Interface) — free, no hourly charge.
> Traffic stays within AWS network. No NAT Gateway needed for DynamoDB from private subnets.

---

## 17. Import & Export

### Export to S3 (no impact on table performance)
```hcl
# Managed via AWS console/CLI; no native Terraform resource
# Use aws CLI:
# aws dynamodb export-table-to-point-in-time \
#   --table-arn arn:aws:dynamodb:us-east-1:123456789012:table/my-table \
#   --s3-bucket my-exports \
#   --s3-prefix dynamodb-exports/ \
#   --export-format DYNAMODB_JSON  # or ION
```

### Import from S3
```bash
aws dynamodb import-table \
  --s3-bucket-source BucketName=my-exports,KeyPrefix=data/ \
  --input-format CSV \
  --table-creation-parameters \
    "TableName=new-table,BillingMode=PAY_PER_REQUEST,AttributeDefinitions=[{AttributeName=pk,AttributeType=S}],KeySchema=[{AttributeName=pk,KeyType=HASH}]"
```

### Export Formats
- `DYNAMODB_JSON` — DynamoDB JSON format with type descriptors.
- `ION` — Apache Ion format.
- `CSV` — only for import, limited to scalar types.

---

## 18. PartiQL

- SQL-compatible query language for DynamoDB.
- Supported in console, AWS CLI, SDK.
- Does NOT change DynamoDB's underlying access pattern costs.
- Scans are still expensive. Filtered queries still read full key range.

```sql
-- Select
SELECT * FROM "my-table" WHERE pk = 'USER#123' AND sk = 'PROFILE'

-- Select with index
SELECT * FROM "my-table"."gsi1" WHERE gsi1pk = 'STATUS#ACTIVE'

-- Insert
INSERT INTO "my-table" VALUE {'pk': 'USER#456', 'sk': 'PROFILE', 'name': 'Bob'}

-- Update
UPDATE "my-table"
SET name = 'Bob Updated', updated_at = '2024-06-01'
WHERE pk = 'USER#456' AND sk = 'PROFILE'

-- Delete
DELETE FROM "my-table"
WHERE pk = 'USER#456' AND sk = 'PROFILE'
```

```python
response = dynamodb.execute_statement(
    Statement="SELECT * FROM \"my-table\" WHERE pk = 'USER#123'",
    ConsistentRead=True,
)
items = response["Items"]
```

---

## 19. Observability — Metrics & Alarms

### Key CloudWatch Metrics (namespace: `AWS/DynamoDB`)

| Metric | Description | Stat |
|---|---|---|
| `ConsumedReadCapacityUnits` | RCUs consumed | Sum, Avg |
| `ConsumedWriteCapacityUnits` | WCUs consumed | Sum, Avg |
| `ProvisionedReadCapacityUnits` | Provisioned RCUs | Avg |
| `ProvisionedWriteCapacityUnits` | Provisioned WCUs | Avg |
| `ReadThrottleEvents` | Throttled read requests | Sum |
| `WriteThrottleEvents` | Throttled write requests | Sum |
| `ThrottledRequests` | Total throttled requests (all ops) | Sum |
| `SystemErrors` | 5xx errors from DynamoDB | Sum |
| `UserErrors` | 4xx errors (bad requests) | Sum |
| `SuccessfulRequestLatency` | Per-operation latency | Avg, p99, Max |
| `ConditionalCheckFailedRequests` | Failed condition checks | Sum |
| `TransactionConflict` | Transaction conflicts | Sum |
| `AccountProvisionedReadCapacityUtilization` | Account-level RCU % | Avg |
| `AccountProvisionedWriteCapacityUtilization` | Account-level WCU % | Avg |
| `MaxProvisionedTableReadCapacityUtilization` | Highest table RCU % | Avg |
| `MaxProvisionedTableWriteCapacityUtilization` | Highest table WCU % | Avg |
| `ReturnedItemCount` | Items returned by Query/Scan | Avg, Sum |

### Dimensions
- `TableName` — per-table metrics.
- `Operation` — GetItem, PutItem, Query, Scan, etc.
- `GlobalSecondaryIndexName` — per-GSI throttle metrics.

### CloudWatch Alarms
```hcl
resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "${var.table_name}-read-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = { TableName = aws_dynamodb_table.this.name }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "${var.table_name}-write-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = { TableName = aws_dynamodb_table.this.name }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "system_errors" {
  alarm_name          = "${var.table_name}-system-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = { TableName = aws_dynamodb_table.this.name }
  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  alarm_name          = "${var.table_name}-getitem-latency-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 50  # ms

  metric_name        = "SuccessfulRequestLatency"
  namespace          = "AWS/DynamoDB"
  period             = 60
  extended_statistic = "p99"

  dimensions = {
    TableName = aws_dynamodb_table.this.name
    Operation = "GetItem"
  }

  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "read_capacity_utilization" {
  alarm_name          = "${var.table_name}-read-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 80  # percent

  # Computed metric: Consumed / Provisioned * 100
  metric_query {
    id          = "consumed"
    return_data = false
    metric {
      metric_name = "ConsumedReadCapacityUnits"
      namespace   = "AWS/DynamoDB"
      period      = 60
      stat        = "Sum"
      dimensions  = { TableName = aws_dynamodb_table.this.name }
    }
  }

  metric_query {
    id          = "provisioned"
    return_data = false
    metric {
      metric_name = "ProvisionedReadCapacityUnits"
      namespace   = "AWS/DynamoDB"
      period      = 60
      stat        = "Average"
      dimensions  = { TableName = aws_dynamodb_table.this.name }
    }
  }

  metric_query {
    id          = "utilization"
    expression  = "(consumed / 60) / provisioned * 100"
    return_data = true
    label       = "Read Capacity Utilization %"
  }

  alarm_actions = [var.alert_sns_arn]
  tags          = var.tags
}
```

### CloudWatch Dashboard
```hcl
resource "aws_cloudwatch_dashboard" "dynamodb" {
  dashboard_name = "${var.table_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title   = "Throttle Events"
          period  = 60
          metrics = [
            ["AWS/DynamoDB", "ReadThrottleEvents",  "TableName", var.table_name, { stat = "Sum", color = "#ff7f0e" }],
            ["AWS/DynamoDB", "WriteThrottleEvents", "TableName", var.table_name, { stat = "Sum", color = "#d62728" }],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Latency p99 by Operation"
          period  = 60
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.table_name, "Operation", "GetItem",   { stat = "p99" }],
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.table_name, "Operation", "PutItem",   { stat = "p99" }],
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.table_name, "Operation", "Query",     { stat = "p99" }],
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.table_name, "Operation", "UpdateItem",{ stat = "p99" }],
          ]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Consumed Capacity"
          period  = 60
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits",  "TableName", var.table_name, { stat = "Sum" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.table_name, { stat = "Sum" }],
          ]
        }
      }
    ]
  })
}
```

---

## 20. Observability — CloudWatch Contributor Insights

- Identifies top N most accessed keys and throttled keys.
- Helps find **hot partitions** and most/least popular items.
- Powered by CloudWatch Logs Insights under the hood.

```hcl
resource "aws_dynamodb_contributor_insights" "this" {
  table_name = aws_dynamodb_table.this.name
  # index_name = "gsi1"  # optional — enable for specific GSI too
}
```

### What Contributor Insights Shows
- Most accessed partition keys.
- Most throttled partition keys (hot partition detection).
- Most accessed items (PK + SK).
- Most throttled items.
- Useful rule: if top key accounts for >50% of traffic → hot partition risk.

---

## 21. Observability — Logging

### CloudTrail for DynamoDB Control Plane
```hcl
resource "aws_cloudtrail" "dynamodb" {
  name                          = "${var.table_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = false
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true  # CreateTable, DeleteTable, UpdateTable, etc.

    # Data events for DynamoDB (captures GetItem, PutItem, etc.)
    data_resource {
      type   = "AWS::DynamoDB::Table"
      values = [aws_dynamodb_table.this.arn]  # or "arn:aws:dynamodb" for all tables
    }
  }

  tags = var.tags
}
```

### CloudTrail Events Logged
- **Management events**: `CreateTable`, `DeleteTable`, `UpdateTable`, `CreateGlobalTable`, `TagResource`, `UntagResource`, `UpdateContinuousBackups`, `RestoreTableToPointInTime`.
- **Data events** (if enabled): `GetItem`, `PutItem`, `UpdateItem`, `DeleteItem`, `BatchGetItem`, `BatchWriteItem`, `Query`, `Scan`, `TransactGetItems`, `TransactWriteItems`.

> Data event logging for DynamoDB is costly — enable only for compliance/audit requirements or on specific tables.

---

## 22. Observability — X-Ray

```python
# Enable X-Ray for DynamoDB boto3 calls
from aws_xray_sdk.core import xray_recorder, patch

patch(["boto3"])  # patches all boto3 clients including DynamoDB

# This automatically creates subsegments for all DynamoDB calls
def handler(event, context):
    table = boto3.resource("dynamodb").Table("my-table")
    response = table.get_item(Key={"pk": "USER#123", "sk": "PROFILE"})
    # X-Ray subsegment created automatically with table name, operation, latency
```

### X-Ray Annotations (custom)
```python
with xray_recorder.in_subsegment("batch-process") as seg:
    seg.put_annotation("table", "my-table")
    seg.put_annotation("item_count", len(items))
    seg.put_metadata("query_params", {"pk": "USER#123"})
    # ... do DynamoDB work
```

---

## 23. Debugging & Troubleshooting

### Common Errors

| Error | Cause | Resolution |
|---|---|---|
| `ProvisionedThroughputExceededException` | RCU or WCU limit hit | Increase capacity, add auto-scaling, use exponential backoff |
| `ConditionalCheckFailedException` | Condition expression evaluated false | Expected state — handle in application logic |
| `TransactionCanceledException` | Transaction condition failed or conflict | Check `CancellationReasons`, retry with backoff |
| `ItemCollectionSizeLimitExceededException` | Item collection (PK + LSI) > 10 GB | Redesign key schema, remove LSI, archive old items |
| `ResourceNotFoundException` | Table/index doesn't exist | Check table name, region, IAM permissions |
| `ValidationException` | Bad request (wrong types, invalid expression) | Check attribute types, expression syntax |
| `RequestLimitExceeded` | Too many concurrent requests to DynamoDB | Implement backoff, connection pooling |
| `InternalServerError` | DynamoDB internal issue | Retry with backoff; if persistent, contact AWS |
| `IdempotentParameterMismatchException` | Same ClientRequestToken used with different params | Use unique tokens per transaction |

### Hot Partition Detection
```
# Symptoms:
- ReadThrottleEvents or WriteThrottleEvents alarm fires
- Contributor Insights shows one key dominating traffic
- Latency spikes on specific operations
- Some requests succeed while identical ones throttle

# Diagnosis:
1. Enable Contributor Insights → check "Most accessed keys"
2. Check CloudWatch metric by Operation dimension
3. Check if a specific access pattern causes the load

# Solutions:
- Write sharding (add random suffix to PK)
- Caching with DAX or ElastiCache
- Redesign access pattern (avoid hot keys)
- Increase provisioned capacity temporarily
- Switch to on-demand mode
```

### Throttling Backoff Pattern (Python)
```python
import time
import random

def dynamodb_with_backoff(operation, max_retries=5):
    for attempt in range(max_retries):
        try:
            return operation()
        except dynamodb.meta.client.exceptions.ProvisionedThroughputExceededException:
            if attempt == max_retries - 1:
                raise
            wait = (2 ** attempt) + random.uniform(0, 1)  # exponential + jitter
            time.sleep(wait)
```

### Pagination — Missing Items Bug
```python
# WRONG — stops at first page
response = table.query(KeyConditionExpression=Key("pk").eq("USER#123"))
items = response["Items"]  # might be incomplete!

# CORRECT — paginate through all results
def query_all(table, **kwargs):
    items = []
    last_key = None
    while True:
        if last_key:
            kwargs["ExclusiveStartKey"] = last_key
        response = table.query(**kwargs)
        items.extend(response["Items"])
        last_key = response.get("LastEvaluatedKey")
        if not last_key:
            break
    return items
```

### Filter Expression vs Key Condition
```
# Misunderstanding: FilterExpression does NOT reduce RCU cost
# DynamoDB reads all items matching KeyCondition, THEN filters

# Example: PK has 10,000 items, filter matches 10
# Cost: 10,000 items worth of RCUs consumed (not 10)

# Solution: Use SK range to narrow results at the key level:
# Bad:  KeyCondition=PK AND FilterExpression=date > X
# Good: KeyCondition=PK AND SK > X
```

### Common Logs Insights Queries (CloudTrail)
```
# Find all table deletions
fields eventTime, userIdentity.arn, requestParameters.tableName
| filter eventName = "DeleteTable"
| sort eventTime desc

# Find all failed DynamoDB data operations
fields eventTime, eventName, errorCode, errorMessage, userIdentity.arn
| filter errorCode exists
| sort eventTime desc

# Most common error types
stats count() by errorCode
| sort count() desc

# Operations by IAM principal
stats count() by eventName, userIdentity.arn
| sort count() desc
```

### Useful AWS CLI Debug Commands
```bash
# Describe table
aws dynamodb describe-table --table-name my-table

# Check continuous backups
aws dynamodb describe-continuous-backups --table-name my-table

# List streams
aws dynamodb list-streams --table-name my-table

# Scan item count (exact)
aws dynamodb scan \
  --table-name my-table \
  --select COUNT

# Describe GSI
aws dynamodb describe-table --table-name my-table \
  --query 'Table.GlobalSecondaryIndexes[*].{Name:IndexName,Status:IndexStatus,ItemCount:ItemCount}'

# List backups
aws dynamodb list-backups --table-name my-table

# Estimate table size
aws dynamodb describe-table --table-name my-table \
  --query 'Table.{ItemCount:ItemCount,TableSizeBytes:TableSizeBytes}'
```

---

## 24. Cost Model

### On-Demand Pricing
- **Reads**: $0.25 per million read request units.
- **Writes**: $1.25 per million write request units.
- **Transactional reads**: 2x read cost.
- **Transactional writes**: 2x write cost.

### Provisioned Pricing
- **Read**: $0.00013 per RCU per hour (~$0.09/month per RCU).
- **Write**: $0.00065 per WCU per hour (~$0.47/month per WCU).
- Substantially cheaper than on-demand at steady high utilization.

### Storage
- **Standard**: $0.25 per GB per month.
- **Infrequent Access**: $0.10 per GB per month.

### Other Costs
- **Global Tables replication**: $0.75 per million replicated WCUs.
- **DynamoDB Streams**: $0.02 per 100,000 read request units (stream reads).
- **PITR**: $0.20 per GB per month (continuous backup storage).
- **On-demand backups**: $0.10 per GB per month.
- **DAX**: Per node-hour ($0.27/hr for r4.large + $0.09/hr data transfer).
- **Exports to S3**: $0.10 per GB exported.
- **Data transfer out**: Standard EC2 rates.

### Cost Optimization Tips
- Use on-demand for bursty/unpredictable; provisioned + auto-scaling for steady.
- Right-size provisioned capacity — avoid over-provisioning.
- Use STANDARD_INFREQUENT_ACCESS for tables with infrequent access patterns.
- Project KEYS_ONLY or INCLUDE (not ALL) on GSIs where possible.
- Use TTL to delete old items (free) instead of explicit DeleteItem.
- Use batch operations to reduce per-request overhead.
- Avoid unnecessary scans (consume a lot of RCU).
- Use Contributor Insights only on tables that need it (small cost).
- Compress large attribute values before storing.
- Reserve capacity for predictable workloads (Reserved Capacity = up to 76% savings).

---

## 25. Limits & Quotas

| Resource | Limit | Adjustable |
|---|---|---|
| Tables per region | 2,500 | Yes |
| GSIs per table | 20 | Yes |
| LSIs per table | 5 | No |
| Item size | 400 KB | No |
| Partition key value size | 2,048 bytes | No |
| Sort key value size | 1,024 bytes | No |
| Attribute name length | 64 KB | No |
| Nesting depth (Map/List) | 32 levels | No |
| BatchGetItem items | 100 / 16 MB | No |
| BatchWriteItem requests | 25 / 16 MB | No |
| TransactGetItems | 100 items | No |
| TransactWriteItems | 100 items | No |
| Query / Scan result page | 1 MB (before filter) | No |
| Provisioned throughput per partition | 3,000 RCU + 1,000 WCU | No |
| On-demand peak RPS per table | 40,000 RCU + 40,000 WCU | Yes |
| Min on-demand capacity | 0 | — |
| Max item collection size (table + LSIs) | 10 GB | No |
| Streams retention | 24 hours | No |
| Global Tables regions | 50 | Yes |
| DAX nodes per cluster | 10 | Yes |
| PITR window | 35 days | No |
| Number of SSE KMS key changes per day | 1 | No |
| Concurrent table creation | 50 | Yes |

---

## 26. Best Practices

### Data Modeling
- Design for access patterns first — list all before writing a line of code.
- Single-table design reduces operational overhead and latency.
- Use composite sort keys for hierarchical relationships.
- Avoid storing blobs/large objects in DynamoDB — store in S3, store S3 key in DynamoDB.
- Keep items small; attributes close to 400 KB limit cause issues at scale.

### Keys & Partitions
- High-cardinality partition keys = even data distribution.
- Never use sequential IDs as PK alone (monotonically increasing = hot partition).
- Use UUID v4 or hash of natural key for PK where appropriate.
- Write sharding for unavoidably hot keys.
- Avoid low-cardinality GSI keys (boolean, status with few values).

### Performance
- `GetItem` > `Query` > `Scan` in efficiency order.
- Use `ProjectionExpression` to fetch only needed attributes.
- Cache with DAX for read-heavy hotspot items.
- Use sparse indexes (GSIs) to avoid index bloat.
- Prefer `UpdateItem` over read-modify-write `PutItem` patterns.
- Use condition expressions for optimistic locking.

### Reliability
- Always enable PITR in production.
- Implement deletion protection on production tables.
- Handle `ProvisionedThroughputExceededException` with exponential backoff + jitter.
- Handle partial batch failures: check `UnprocessedKeys` / `UnprocessedItems`.
- Use `ClientRequestToken` for transaction idempotency.
- Test with `ReturnConsumedCapacity = "TOTAL"` to understand cost.

### Operations
- Always create with `deletion_protection_enabled = true`.
- Tag all tables for cost allocation.
- Monitor throttle alarms and act on them quickly.
- Enable Contributor Insights on production tables.
- Use on-demand for new tables; switch to provisioned once traffic patterns are understood.
- Keep auto-scaling scale-out cooldown low (60s) and scale-in high (300s).

---

## 27. Terraform Full Resource Reference

### Complete DynamoDB Module

```hcl
##############################################
# variables.tf
##############################################
variable "table_name"              { type = string }
variable "environment"             { type = string }
variable "hash_key"                { default = "pk" }
variable "sort_key"                { default = "sk" }
variable "billing_mode"            { default = "PAY_PER_REQUEST" }
variable "read_capacity"           { default = 5 }
variable "write_capacity"          { default = 5 }
variable "autoscaling_min_read"    { default = 5 }
variable "autoscaling_max_read"    { default = 1000 }
variable "autoscaling_min_write"   { default = 5 }
variable "autoscaling_max_write"   { default = 500 }
variable "autoscaling_target_pct"  { default = 70 }
variable "ttl_attribute"           { default = "expires_at" }
variable "ttl_enabled"             { default = true }
variable "enable_streams"          { default = false }
variable "stream_view_type"        { default = "NEW_AND_OLD_IMAGES" }
variable "enable_pitr"             { default = true }
variable "kms_key_arn"             { default = null }
variable "table_class"             { default = "STANDARD" }
variable "enable_contributor_insights" { default = true }
variable "enable_deletion_protection"  { default = true }
variable "alert_sns_arn"           { type = string }
variable "tags"                    { default = {} }
variable "gsi_definitions"         { default = [] }
# gsi_definitions = [{
#   name               = "gsi1"
#   hash_key           = "gsi1pk"
#   hash_key_type      = "S"
#   range_key          = "gsi1sk"
#   range_key_type     = "S"
#   projection_type    = "ALL"
#   non_key_attributes = []
# }]

##############################################
# main.tf
##############################################

locals {
  is_provisioned = var.billing_mode == "PROVISIONED"

  # Collect all unique attribute definitions (table keys + GSI keys)
  gsi_attributes = distinct(flatten([
    for gsi in var.gsi_definitions : [
      { name = gsi.hash_key, type = gsi.hash_key_type },
      gsi.range_key != null ? { name = gsi.range_key, type = gsi.range_key_type } : null
    ] if gsi != null
  ]))
}

resource "aws_dynamodb_table" "this" {
  name             = var.table_name
  billing_mode     = var.billing_mode
  hash_key         = var.hash_key
  sort_key         = var.sort_key
  table_class      = var.table_class

  read_capacity  = local.is_provisioned ? var.read_capacity : null
  write_capacity = local.is_provisioned ? var.write_capacity : null

  # Base table key attributes
  attribute {
    name = var.hash_key
    type = "S"
  }

  attribute {
    name = var.sort_key
    type = "S"
  }

  # Dynamic GSIs
  dynamic "global_secondary_index" {
    for_each = var.gsi_definitions
    content {
      name               = global_secondary_index.value.name
      hash_key           = global_secondary_index.value.hash_key
      range_key          = lookup(global_secondary_index.value, "range_key", null)
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null
      read_capacity      = local.is_provisioned ? lookup(global_secondary_index.value, "read_capacity", var.read_capacity) : null
      write_capacity     = local.is_provisioned ? lookup(global_secondary_index.value, "write_capacity", var.write_capacity) : null
    }
  }

  ttl {
    attribute_name = var.ttl_attribute
    enabled        = var.ttl_enabled
  }

  stream_enabled   = var.enable_streams
  stream_view_type = var.enable_streams ? var.stream_view_type : null

  point_in_time_recovery {
    enabled = var.enable_pitr
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn  # null = AWS-owned key
  }

  deletion_protection_enabled = var.enable_deletion_protection

  tags = merge(var.tags, {
    Environment = var.environment
    Table       = var.table_name
  })

  lifecycle {
    prevent_destroy = true  # additional safety
  }
}

# --- Auto-scaling (only for PROVISIONED) ---
resource "aws_appautoscaling_target" "read" {
  count              = local.is_provisioned ? 1 : 0
  max_capacity       = var.autoscaling_max_read
  min_capacity       = var.autoscaling_min_read
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "read" {
  count              = local.is_provisioned ? 1 : 0
  name               = "${var.table_name}-read-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read[0].resource_id
  scalable_dimension = aws_appautoscaling_target.read[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.read[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_target_pct
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "write" {
  count              = local.is_provisioned ? 1 : 0
  max_capacity       = var.autoscaling_max_write
  min_capacity       = var.autoscaling_min_write
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "write" {
  count              = local.is_provisioned ? 1 : 0
  name               = "${var.table_name}-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_target_pct
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
  }
}

# --- Contributor Insights ---
resource "aws_dynamodb_contributor_insights" "this" {
  count      = var.enable_contributor_insights ? 1 : 0
  table_name = aws_dynamodb_table.this.name
}

# --- Alarms ---
resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "${var.table_name}-read-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { TableName = aws_dynamodb_table.this.name }
  alarm_actions       = [var.alert_sns_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "${var.table_name}-write-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { TableName = aws_dynamodb_table.this.name }
  alarm_actions       = [var.alert_sns_arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "system_errors" {
  alarm_name          = "${var.table_name}-system-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { TableName = aws_dynamodb_table.this.name }
  alarm_actions       = [var.alert_sns_arn]
  tags                = var.tags
}

##############################################
# outputs.tf
##############################################
output "table_name"        { value = aws_dynamodb_table.this.name }
output "table_arn"         { value = aws_dynamodb_table.this.arn }
output "table_id"          { value = aws_dynamodb_table.this.id }
output "stream_arn"        { value = aws_dynamodb_table.this.stream_arn }
output "stream_label"      { value = aws_dynamodb_table.this.stream_label }
output "hash_key"          { value = aws_dynamodb_table.this.hash_key }
output "sort_key"          { value = aws_dynamodb_table.this.sort_key }
```

---

### Terraform Resource Quick Reference Table

| Resource | Purpose |
|---|---|
| `aws_dynamodb_table` | Core table with keys, GSIs, LSIs, streams, TTL, SSE, PITR |
| `aws_dynamodb_table_item` | Manage individual items (dev/seeding only, not for production) |
| `aws_dynamodb_contributor_insights` | Enable Contributor Insights per table or GSI |
| `aws_dynamodb_kinesis_streaming_destination` | Replicate changes to Kinesis Data Stream |
| `aws_dynamodb_resource_policy` | Resource-based policy (cross-account) |
| `aws_dynamodb_global_table` | Global Table v1 (legacy — use `replica` block in `aws_dynamodb_table` for v2) |
| `aws_appautoscaling_target` | Auto-scaling target for read/write capacity or GSI |
| `aws_appautoscaling_policy` | Target-tracking scaling policy |
| `aws_dax_cluster` | DAX in-memory cache cluster |
| `aws_dax_subnet_group` | Subnets for DAX cluster |
| `aws_dax_parameter_group` | DAX cache TTL settings |
| `aws_backup_plan` | Automated backup schedule |
| `aws_backup_selection` | Select table for backup plan |
| `aws_backup_vault` | Vault to store backups |
| `aws_kms_key` | Customer-managed encryption key |
| `aws_kms_alias` | Human-friendly alias for KMS key |
| `aws_vpc_endpoint` | Gateway endpoint for DynamoDB (free) |
| `aws_cloudwatch_metric_alarm` | Throttle, error, latency alarms |
| `aws_cloudwatch_dashboard` | Operational dashboard |
| `aws_cloudtrail` | Control/data plane audit logging |
| `aws_lambda_event_source_mapping` | Stream → Lambda trigger |
| `aws_iam_role_policy` | IAM policy for table access |

---

*Last updated: February 2026*
*Next: SQS, EventBridge, Step Functions, ECS, RDS, ElastiCache, S3*