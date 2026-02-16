# DynamoDB Complete Reference Guide

## Table of Contents
- [Introduction](#introduction)
- [Core Concepts](#core-concepts)
- [Table Design](#table-design)
- [Primary Keys](#primary-keys)
- [Secondary Indexes](#secondary-indexes)
- [Data Types](#data-types)
- [Capacity Modes](#capacity-modes)
- [Read and Write Operations](#read-and-write-operations)
- [Conditional Operations](#conditional-operations)
- [Transactions](#transactions)
- [Batch Operations](#batch-operations)
- [Streams](#streams)
- [Global Tables](#global-tables)
- [Point-in-Time Recovery](#point-in-time-recovery)
- [Encryption](#encryption)
- [Best Practices](#best-practices)
- [Performance Optimization](#performance-optimization)
- [Cost Optimization](#cost-optimization)
- [Terraform Examples](#terraform-examples)
- [Advanced Patterns](#advanced-patterns)
- [Troubleshooting](#troubleshooting)

---

## Introduction

Amazon DynamoDB is a fully managed NoSQL database service that provides fast and predictable performance with seamless scalability. It's a key-value and document database that delivers single-digit millisecond performance at any scale.

### Key Characteristics
- **Fully Managed**: AWS handles hardware provisioning, setup, configuration, replication, software patching, and cluster scaling
- **Performance**: Consistent single-digit millisecond latency at any scale
- **Scalability**: Automatic scaling from zero to millions of requests per second
- **Durability**: Data is automatically replicated across multiple Availability Zones
- **Security**: Encryption at rest and in transit, fine-grained access control via IAM
- **Serverless**: No servers to provision or manage

### When to Use DynamoDB
- Applications requiring consistent, single-digit millisecond latency
- Serverless applications
- Mobile and web applications
- Gaming applications
- IoT applications
- Real-time bidding
- Shopping carts
- Session stores

---

## Core Concepts

### Tables
A table is a collection of items. Unlike relational databases, DynamoDB tables are schemaless (except for the primary key).

**Key Points**:
- Table names must be unique within an AWS account and region
- No practical limit on the number of items
- No limit on table size
- Items can have different attributes (schema flexibility)

### Items
An item is a group of attributes uniquely identifiable among all other items. Similar to a row in a relational database.

**Characteristics**:
- Maximum item size: 400 KB (including attribute names and values)
- Each item must have the primary key attributes
- Can have nested attributes up to 32 levels deep
- No limit on the number of attributes (within 400 KB limit)

### Attributes
An attribute is a fundamental data element. Similar to a column in a relational database, but items can have different attributes.

**Types of Attributes**:
- **Scalar Types**: String, Number, Binary, Boolean, Null
- **Document Types**: List, Map
- **Set Types**: String Set, Number Set, Binary Set

### Primary Key
Uniquely identifies each item in a table. DynamoDB supports two types of primary keys:

1. **Partition Key** (Simple Primary Key): Single attribute
2. **Partition Key + Sort Key** (Composite Primary Key): Two attributes

---

## Table Design

### Designing for NoSQL

DynamoDB is fundamentally different from relational databases. Design principles:

#### 1. Understand Your Access Patterns First
- List all queries your application needs
- Identify access patterns before creating tables
- Design tables to support specific queries efficiently

#### 2. One Table Design (Advanced Pattern)
- Store multiple entity types in a single table
- Use generic attribute names (PK, SK, GSI1PK, GSI1SK)
- Leverage composite keys and overloaded indexes
- Reduces costs and improves performance

#### 3. Denormalization is Normal
- Duplicate data across items to avoid joins
- Pre-compute aggregations
- Store data in the format you'll query it

#### 4. Avoid Hot Partitions
- Distribute requests evenly across partition keys
- Add randomness to partition keys if needed (write sharding)
- Use composite sort keys for time-series data

### Partition Key Selection

The partition key determines data distribution and query performance.

**Good Partition Key Characteristics**:
- High cardinality (many distinct values)
- Even request distribution
- Allows efficient queries

**Examples**:
```
Good: UserID, DeviceID, OrderID
Bad: Status (limited values), Country (skewed distribution), Date (hot partitions)
```

**Composite Keys**:
```
Partition Key: UserID
Sort Key: Timestamp

Enables queries like:
- Get all items for a user
- Get items for a user within a time range
- Get the latest N items for a user
```

---

## Primary Keys

### Partition Key (Hash Key)

A single attribute that DynamoDB uses to distribute data across partitions.

**Characteristics**:
- Must be unique across all items (if used alone)
- DynamoDB uses an internal hash function to determine partition
- Cannot be updated after item creation

**Example**:
```json
{
  "UserID": "user123",
  "Email": "user@example.com",
  "Name": "John Doe"
}
```

### Composite Primary Key (Partition + Sort Key)

Two attributes that together uniquely identify an item.

**Characteristics**:
- Partition key groups related items
- Sort key orders items within a partition
- Multiple items can share the same partition key
- Enables range queries using comparison operators
- Both attributes together must be unique

**Example**:
```json
{
  "UserID": "user123",        // Partition Key
  "OrderDate": "2024-01-15",  // Sort Key
  "OrderID": "order456",
  "Amount": 99.99
}
```

### Sort Key Query Operators

When using composite keys, you can query with these operators:

- `=` (Equal)
- `<` (Less than)
- `<=` (Less than or equal)
- `>` (Greater than)
- `>=` (Greater than or equal)
- `BETWEEN`
- `begins_with` (for strings)

**Query Examples**:
```python
# Get all orders for a user
partition_key = "user123"

# Get orders after a specific date
partition_key = "user123"
sort_key > "2024-01-01"

# Get orders in a date range
partition_key = "user123"
sort_key BETWEEN "2024-01-01" AND "2024-12-31"

# Get orders for a specific year and month
partition_key = "user123"
sort_key begins_with "2024-01"
```

### Key Design Patterns

#### Pattern 1: Hierarchical Data
```
PK: CountryID
SK: State#City#Street

Examples:
PK: "USA", SK: "CA#SanFrancisco#MarketSt"
PK: "USA", SK: "CA#LosAngeles#MainSt"
```

#### Pattern 2: Time-Series Data
```
PK: DeviceID
SK: Timestamp (ISO 8601)

Examples:
PK: "device123", SK: "2024-01-15T10:30:00Z"
PK: "device123", SK: "2024-01-15T10:31:00Z"
```

#### Pattern 3: Version Control
```
PK: DocumentID
SK: Version#Timestamp

Examples:
PK: "doc123", SK: "v1#2024-01-15T10:00:00Z"
PK: "doc123", SK: "v2#2024-01-15T11:00:00Z"
```

---

## Secondary Indexes

Secondary indexes allow you to query data using alternate keys beyond the primary key.

### Global Secondary Index (GSI)

An index with a partition key and optional sort key that can be different from the table's primary key.

**Characteristics**:
- Can be created at table creation or added later
- Has its own provisioned throughput (for provisioned mode)
- Queries are eventually consistent (default) or strongly consistent (not available for GSI)
- Maximum 20 GSIs per table
- Projected attributes: Keys only, Include, or All
- Sparse index: Only items with index key attributes are indexed

**Example Use Case**:
```
Base Table:
PK: OrderID
SK: -

GSI:
PK: CustomerID
SK: OrderDate

Enables: Query all orders for a customer sorted by date
```

**Important Considerations**:
- GSIs are eventually consistent
- Updates to base table are propagated asynchronously
- If GSI runs out of capacity, base table writes can be throttled
- Each GSI consumes additional storage

### Local Secondary Index (LSI)

An index with the same partition key as the table but a different sort key.

**Characteristics**:
- Must be created at table creation time (cannot be added later)
- Shares throughput with the base table
- Can be strongly consistent or eventually consistent
- Maximum 5 LSIs per table
- All LSI items must be <= 10 GB per partition key value
- Only useful with composite primary keys

**Example Use Case**:
```
Base Table:
PK: UserID
SK: Timestamp

LSI:
PK: UserID (same as base table)
SK: Category

Enables: Query user's items by category instead of timestamp
```

**LSI vs GSI Comparison**:

| Feature | LSI | GSI |
|---------|-----|-----|
| Creation | Only at table creation | Anytime |
| Partition Key | Same as base table | Can be different |
| Sort Key | Different from base table | Can be different |
| Throughput | Shares with base table | Independent |
| Consistency | Strong or eventual | Eventually consistent |
| Limit | 5 per table | 20 per table |

### Projection Types

Determines which attributes are copied to the index:

#### 1. KEYS_ONLY
- Only the index keys and primary key attributes
- Smallest index size
- Lowest cost

#### 2. INCLUDE
- Index keys, primary key, plus specified attributes
- Balance between size and flexibility

#### 3. ALL
- All attributes from the base table
- Largest index size
- Highest cost
- No need to fetch from base table

**Example**:
```python
# Query a GSI - only projected attributes are returned without additional fetch
response = table.query(
    IndexName='CustomerID-OrderDate-index',
    KeyConditionExpression=Key('CustomerID').eq('customer123')
)

# If you need non-projected attributes, DynamoDB fetches from base table
response = table.query(
    IndexName='CustomerID-OrderDate-index',
    KeyConditionExpression=Key('CustomerID').eq('customer123'),
    ProjectionExpression='OrderID, CustomerID, OrderDate, ProductDetails'  # ProductDetails not projected
)
```

### Sparse Indexes

A powerful pattern where only items with the index key attributes appear in the index.

**Use Case**: Filter for items with specific characteristics

**Example**:
```
Base Table (all items):
- OrderID: "order1", Status: "COMPLETED"
- OrderID: "order2", Status: "PENDING"
- OrderID: "order3", Status: "COMPLETED"

GSI with PK: StatusPending (sparse attribute):
- Only items with StatusPending attribute appear in index
- Set StatusPending="PENDING" only for pending orders
- GSI only contains pending orders

Benefits:
- Smaller index size
- Cheaper storage
- Faster queries
- Easy to query just pending orders
```

---

## Data Types

### Scalar Types

#### String
- UTF-8 encoded
- Maximum 400 KB per attribute
- Used for text data
- Can be used in primary keys and indexes

```json
{
  "Name": "John Doe",
  "Email": "john@example.com"
}
```

#### Number
- Can be positive, negative, or zero
- Up to 38 digits of precision
- Represented as strings in JSON
- Used for numeric calculations

```json
{
  "Price": 29.99,
  "Quantity": 100,
  "Score": -15
}
```

#### Binary
- Base64-encoded before sending to DynamoDB
- Used for compressed data, encrypted data, images (small)

```json
{
  "Image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
}
```

#### Boolean
- True or false values

```json
{
  "IsActive": true,
  "EmailVerified": false
}
```

#### Null
- Represents an unknown or undefined state

```json
{
  "MiddleName": null
}
```

### Document Types

#### List
- Ordered collection of values
- Can contain different data types
- Nested up to 32 levels

```json
{
  "Tags": ["important", "urgent", "review"],
  "Scores": [95, 87, 92],
  "Mixed": ["string", 123, true, null]
}
```

#### Map
- Unordered collection of name-value pairs
- Similar to JSON objects
- Nested up to 32 levels

```json
{
  "Address": {
    "Street": "123 Main St",
    "City": "San Francisco",
    "State": "CA",
    "ZipCode": "94102",
    "Coordinates": {
      "Latitude": 37.7749,
      "Longitude": -122.4194
    }
  }
}
```

### Set Types

Sets are unique collections of scalar values. No duplicates allowed.

#### String Set (SS)
```json
{
  "Interests": ["hiking", "reading", "coding"]
}
```

#### Number Set (NS)
```json
{
  "Scores": [95, 87, 92, 88]
}
```

#### Binary Set (BS)
```json
{
  "Images": ["base64data1", "base64data2"]
}
```

**Set Characteristics**:
- All values must be the same type
- No duplicates
- Unordered
- Empty sets not allowed
- Useful for ADD and DELETE operations

---

## Capacity Modes

### On-Demand Mode

Pay per request pricing with automatic scaling.

**Characteristics**:
- No capacity planning required
- Automatically scales up and down
- Pay only for what you use
- Good for unpredictable workloads
- Good for new applications with unknown traffic
- Can handle up to 2x previous peak within 30 minutes

**Pricing Model**:
- Per read request unit (RRU)
- Per write request unit (WRU)
- No minimum capacity
- No charges for idle time

**Use Cases**:
- Unpredictable traffic patterns
- New applications
- Spiky workloads
- Pay-as-you-go preference

**Terraform Example**:
```hcl
resource "aws_dynamodb_table" "on_demand_table" {
  name         = "OnDemandTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }
}
```

### Provisioned Mode

Specify read and write capacity units in advance.

**Characteristics**:
- Predictable performance
- Reserved capacity for cost optimization
- Auto-scaling available
- More cost-effective for steady workloads

**Capacity Units**:

**Read Capacity Unit (RCU)**:
- 1 RCU = 1 strongly consistent read per second for items up to 4 KB
- 1 RCU = 2 eventually consistent reads per second for items up to 4 KB
- Larger items consume more RCUs (round up to next 4 KB)

**Write Capacity Unit (WCU)**:
- 1 WCU = 1 write per second for items up to 1 KB
- Larger items consume more WCUs (round up to next 1 KB)

**Calculation Examples**:

```
Read Capacity Calculation:
- Item size: 8 KB
- Strongly consistent reads: 10 per second
- RCUs needed: (8 KB / 4 KB) * 10 = 20 RCUs

- Item size: 8 KB
- Eventually consistent reads: 10 per second
- RCUs needed: (8 KB / 4 KB) * 10 / 2 = 10 RCUs

Write Capacity Calculation:
- Item size: 3 KB
- Writes: 10 per second
- WCUs needed: (3 KB / 1 KB) * 10 = 30 WCUs
```

**Auto-Scaling**:
```hcl
resource "aws_dynamodb_table" "provisioned_table" {
  name         = "ProvisionedTable"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.provisioned_table.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  name               = "DynamoDBReadCapacityUtilization"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70.0
  }
}
```

### Reserved Capacity

Commit to a minimum provisioned capacity for a 1 or 3-year term.

**Benefits**:
- Significant cost savings (up to 76% discount)
- Only available for provisioned mode
- Applied automatically to matching tables

---

## Read and Write Operations

### PutItem

Creates a new item or replaces an existing item.

**Characteristics**:
- Requires primary key attributes
- Replaces entire item if it exists
- Consumes write capacity
- Can use condition expressions

**Example**:
```python
import boto3
from boto3.dynamodb.conditions import Attr

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Users')

response = table.put_item(
    Item={
        'UserID': 'user123',
        'Name': 'John Doe',
        'Email': 'john@example.com',
        'CreatedAt': '2024-01-15T10:00:00Z'
    },
    ConditionExpression=Attr('UserID').not_exists()  # Only put if doesn't exist
)
```

### GetItem

Retrieves a single item by primary key.

**Characteristics**:
- Requires exact primary key
- Returns the entire item (or projected attributes)
- Strongly consistent by default (can use eventually consistent)
- Consumes read capacity

**Example**:
```python
response = table.get_item(
    Key={
        'UserID': 'user123'
    },
    ConsistentRead=True,  # Strongly consistent read
    ProjectionExpression='UserID, Name, Email'  # Return specific attributes only
)

item = response.get('Item')
```

### UpdateItem

Modifies an existing item's attributes or creates a new item.

**Characteristics**:
- Can update specific attributes without replacing entire item
- Supports atomic counters and set operations
- Can return old or new values
- More efficient than GetItem + PutItem

**Update Expressions**:
- `SET`: Modify or add attributes
- `REMOVE`: Delete attributes
- `ADD`: Increment/decrement numbers, add to sets
- `DELETE`: Remove from sets

**Example**:
```python
response = table.update_item(
    Key={
        'UserID': 'user123'
    },
    UpdateExpression='SET Email = :email, UpdatedAt = :timestamp ADD LoginCount :inc',
    ExpressionAttributeValues={
        ':email': 'newemail@example.com',
        ':timestamp': '2024-01-15T11:00:00Z',
        ':inc': 1
    },
    ReturnValues='ALL_NEW'  # Return the updated item
)
```

**Complex Update Example**:
```python
response = table.update_item(
    Key={'UserID': 'user123'},
    UpdateExpression='''
        SET #name = :name,
            Address.City = :city,
            Tags = list_append(if_not_exists(Tags, :empty_list), :new_tags)
        REMOVE TempField
        ADD LoginCount :inc
        DELETE Interests :old_interest
    ''',
    ExpressionAttributeNames={
        '#name': 'Name'  # 'Name' is a reserved word
    },
    ExpressionAttributeValues={
        ':name': 'Jane Doe',
        ':city': 'New York',
        ':new_tags': ['premium'],
        ':empty_list': [],
        ':inc': 1,
        ':old_interest': {'reading'}
    }
)
```

### DeleteItem

Removes an item from the table.

**Example**:
```python
response = table.delete_item(
    Key={
        'UserID': 'user123'
    },
    ConditionExpression=Attr('Status').eq('INACTIVE'),  # Only delete if inactive
    ReturnValues='ALL_OLD'  # Return the deleted item
)
```

### Query

Retrieves items with the same partition key, optionally filtered by sort key.

**Characteristics**:
- Most efficient way to retrieve multiple items
- Requires partition key
- Can filter on sort key with comparison operators
- Returns items in sort key order (ascending or descending)
- Maximum 1 MB of data per query
- Can be eventually or strongly consistent

**Example**:
```python
from boto3.dynamodb.conditions import Key

# Query with partition key only
response = table.query(
    KeyConditionExpression=Key('UserID').eq('user123')
)

# Query with partition key and sort key range
response = table.query(
    KeyConditionExpression=Key('UserID').eq('user123') & Key('OrderDate').between('2024-01-01', '2024-12-31'),
    ScanIndexForward=False,  # Descending order
    Limit=10  # Return max 10 items
)

# Query with filter expression
response = table.query(
    KeyConditionExpression=Key('UserID').eq('user123'),
    FilterExpression=Attr('Amount').gt(100)  # Additional filter (applied after query)
)
```

**Pagination**:
```python
response = table.query(
    KeyConditionExpression=Key('UserID').eq('user123')
)

items = response['Items']

# Check if there are more results
while 'LastEvaluatedKey' in response:
    response = table.query(
        KeyConditionExpression=Key('UserID').eq('user123'),
        ExclusiveStartKey=response['LastEvaluatedKey']
    )
    items.extend(response['Items'])
```

### Scan

Examines every item in the table or index.

**Characteristics**:
- Reads every item (expensive)
- Can filter results, but filters applied after reading
- Returns maximum 1 MB per scan
- Eventually consistent by default
- Parallel scans available for faster processing
- Should be avoided in production for large tables

**Example**:
```python
# Basic scan
response = table.scan(
    FilterExpression=Attr('Status').eq('ACTIVE')
)

# Scan with projection
response = table.scan(
    FilterExpression=Attr('Status').eq('ACTIVE'),
    ProjectionExpression='UserID, Name, Email'
)

# Parallel scan (4 segments)
def scan_segment(segment, total_segments):
    response = table.scan(
        FilterExpression=Attr('Status').eq('ACTIVE'),
        Segment=segment,
        TotalSegments=total_segments
    )
    return response['Items']

from concurrent.futures import ThreadPoolExecutor

with ThreadPoolExecutor(max_workers=4) as executor:
    futures = [executor.submit(scan_segment, i, 4) for i in range(4)]
    all_items = []
    for future in futures:
        all_items.extend(future.result())
```

**Query vs Scan**:

| Feature | Query | Scan |
|---------|-------|------|
| Efficiency | High | Low |
| Cost | Low (only reads matched items) | High (reads all items) |
| Requires | Partition key | None |
| Use Case | Retrieve specific items | Retrieve all items or filter entire table |

---

## Conditional Operations

Conditional operations allow you to execute operations only when certain conditions are met.

### Condition Expressions

**Comparison Operators**:
- `=` Equal
- `<>` Not equal
- `<` Less than
- `<=` Less than or equal
- `>` Greater than
- `>=` Greater than or equal

**Logical Operators**:
- `AND`
- `OR`
- `NOT`

**Functions**:
- `attribute_exists(path)`: True if attribute exists
- `attribute_not_exists(path)`: True if attribute doesn't exist
- `attribute_type(path, type)`: Check attribute type
- `begins_with(path, substr)`: String starts with
- `contains(path, operand)`: String contains or set contains
- `size(path)`: Length of string, binary, set, list, or map

**Examples**:

```python
# Put item only if it doesn't exist
table.put_item(
    Item={'UserID': 'user123', 'Name': 'John'},
    ConditionExpression='attribute_not_exists(UserID)'
)

# Update only if version matches (optimistic locking)
table.update_item(
    Key={'UserID': 'user123'},
    UpdateExpression='SET #data = :data, Version = Version + :inc',
    ConditionExpression='Version = :expected_version',
    ExpressionAttributeNames={'#data': 'Data'},
    ExpressionAttributeValues={
        ':data': 'new data',
        ':inc': 1,
        ':expected_version': 5
    }
)

# Delete only if status is inactive and last login was over a year ago
table.delete_item(
    Key={'UserID': 'user123'},
    ConditionExpression='#status = :status AND LastLogin < :cutoff_date',
    ExpressionAttributeNames={'#status': 'Status'},
    ExpressionAttributeValues={
        ':status': 'INACTIVE',
        ':cutoff_date': '2023-01-01'
    }
)

# Update only if email is not set or price is within range
table.update_item(
    Key={'ProductID': 'prod123'},
    UpdateExpression='SET Price = :price',
    ConditionExpression='attribute_not_exists(Email) OR (Price BETWEEN :min AND :max)',
    ExpressionAttributeValues={
        ':price': 99.99,
        ':min': 50,
        ':max': 150
    }
)
```

### Conditional Writes Use Cases

#### 1. Optimistic Locking (Version Control)
```python
# Read item with version
response = table.get_item(Key={'UserID': 'user123'})
item = response['Item']
current_version = item['Version']

# Update with version check
try:
    table.update_item(
        Key={'UserID': 'user123'},
        UpdateExpression='SET #data = :data, Version = :new_version',
        ConditionExpression='Version = :current_version',
        ExpressionAttributeNames={'#data': 'Data'},
        ExpressionAttributeValues={
            ':data': 'updated data',
            ':current_version': current_version,
            ':new_version': current_version + 1
        }
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
        print("Version conflict - item was modified by another process")
```

#### 2. Prevent Duplicate Writes
```python
# Create item only if it doesn't exist
table.put_item(
    Item={
        'RequestID': 'req123',
        'Data': 'Important data',
        'CreatedAt': datetime.now().isoformat()
    },
    ConditionExpression='attribute_not_exists(RequestID)'
)
```

#### 3. Atomic Counter with Limit
```python
# Increment counter only if below limit
table.update_item(
    Key={'CounterID': 'visitor_count'},
    UpdateExpression='ADD #count :inc',
    ConditionExpression='#count < :limit',
    ExpressionAttributeNames={'#count': 'Count'},
    ExpressionAttributeValues={
        ':inc': 1,
        ':limit': 1000
    }
)
```

---

## Transactions

DynamoDB transactions provide ACID properties across one or more items in one or more tables.

### Transaction Types

#### 1. TransactWriteItems

Execute up to 100 write actions atomically.

**Characteristics**:
- All or nothing execution
- Up to 100 items
- Up to 4 MB total size
- Supports Put, Update, Delete, ConditionCheck
- 2x write capacity consumption
- Isolation levels: Read committed

**Example**:
```python
from boto3.dynamodb.conditions import Attr

try:
    response = dynamodb.meta.client.transact_write_items(
        TransactItems=[
            {
                'Put': {
                    'TableName': 'Orders',
                    'Item': {
                        'OrderID': {'S': 'order123'},
                        'UserID': {'S': 'user123'},
                        'Amount': {'N': '99.99'},
                        'Status': {'S': 'PENDING'}
                    },
                    'ConditionExpression': 'attribute_not_exists(OrderID)'
                }
            },
            {
                'Update': {
                    'TableName': 'Users',
                    'Key': {
                        'UserID': {'S': 'user123'}
                    },
                    'UpdateExpression': 'SET Balance = Balance - :amount',
                    'ConditionExpression': 'Balance >= :amount',
                    'ExpressionAttributeValues': {
                        ':amount': {'N': '99.99'}
                    }
                }
            },
            {
                'Update': {
                    'TableName': 'Inventory',
                    'Key': {
                        'ProductID': {'S': 'prod456'}
                    },
                    'UpdateExpression': 'SET Stock = Stock - :qty',
                    'ConditionExpression': 'Stock >= :qty',
                    'ExpressionAttributeValues': {
                        ':qty': {'N': '1'}
                    }
                }
            }
        ]
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'TransactionCanceledException':
        print("Transaction cancelled:", e.response['Error']['Message'])
```

#### 2. TransactGetItems

Retrieve up to 100 items atomically.

**Example**:
```python
response = dynamodb.meta.client.transact_get_items(
    TransactItems=[
        {
            'Get': {
                'TableName': 'Users',
                'Key': {
                    'UserID': {'S': 'user123'}
                },
                'ProjectionExpression': 'UserID, Balance, Email'
            }
        },
        {
            'Get': {
                'TableName': 'Orders',
                'Key': {
                    'OrderID': {'S': 'order123'}
                }
            }
        }
    ]
)

items = [item.get('Item') for item in response['Responses']]
```

### Transaction Use Cases

#### Use Case 1: Money Transfer
```python
def transfer_money(from_user, to_user, amount):
    """Transfer money between users atomically"""
    try:
        dynamodb.meta.client.transact_write_items(
            TransactItems=[
                {
                    'Update': {
                        'TableName': 'Users',
                        'Key': {'UserID': {'S': from_user}},
                        'UpdateExpression': 'SET Balance = Balance - :amount',
                        'ConditionExpression': 'Balance >= :amount',
                        'ExpressionAttributeValues': {
                            ':amount': {'N': str(amount)}
                        }
                    }
                },
                {
                    'Update': {
                        'TableName': 'Users',
                        'Key': {'UserID': {'S': to_user}},
                        'UpdateExpression': 'SET Balance = Balance + :amount',
                        'ExpressionAttributeValues': {
                            ':amount': {'N': str(amount)}
                        }
                    }
                },
                {
                    'Put': {
                        'TableName': 'Transactions',
                        'Item': {
                            'TransactionID': {'S': str(uuid.uuid4())},
                            'FromUser': {'S': from_user},
                            'ToUser': {'S': to_user},
                            'Amount': {'N': str(amount)},
                            'Timestamp': {'S': datetime.now().isoformat()}
                        }
                    }
                }
            ]
        )
        return True
    except ClientError as e:
        print(f"Transfer failed: {e}")
        return False
```

#### Use Case 2: Multi-Table Consistency
```python
def create_order_with_inventory(order_data, product_id, quantity):
    """Create order and update inventory atomically"""
    try:
        dynamodb.meta.client.transact_write_items(
            TransactItems=[
                {
                    'Put': {
                        'TableName': 'Orders',
                        'Item': {
                            'OrderID': {'S': order_data['order_id']},
                            'UserID': {'S': order_data['user_id']},
                            'ProductID': {'S': product_id},
                            'Quantity': {'N': str(quantity)},
                            'Status': {'S': 'CONFIRMED'}
                        }
                    }
                },
                {
                    'Update': {
                        'TableName': 'Inventory',
                        'Key': {'ProductID': {'S': product_id}},
                        'UpdateExpression': 'SET Stock = Stock - :qty',
                        'ConditionExpression': 'Stock >= :qty AND #status = :active',
                        'ExpressionAttributeNames': {
                            '#status': 'Status'
                        },
                        'ExpressionAttributeValues': {
                            ':qty': {'N': str(quantity)},
                            ':active': {'S': 'ACTIVE'}
                        }
                    }
                }
            ]
        )
        return True
    except ClientError as e:
        print(f"Order creation failed: {e}")
        return False
```

### Transaction Best Practices

1. **Keep transactions small**: Fewer items = better performance
2. **Use condition checks**: Ensure data integrity
3. **Handle conflicts**: Implement retry logic with exponential backoff
4. **Monitor capacity**: Transactions consume 2x capacity
5. **Idempotency**: Use unique transaction IDs to prevent duplicates

---

## Batch Operations

Batch operations allow you to work with multiple items in a single request.

### BatchGetItem

Retrieve up to 100 items from one or more tables.

**Characteristics**:
- Up to 100 items per request
- Up to 16 MB of data
- Can read from multiple tables
- Individual items may fail
- UnprocessedKeys returned for retries

**Example**:
```python
response = dynamodb.batch_get_item(
    RequestItems={
        'Users': {
            'Keys': [
                {'UserID': 'user1'},
                {'UserID': 'user2'},
                {'UserID': 'user3'}
            ],
            'ProjectionExpression': 'UserID, Name, Email'
        },
        'Orders': {
            'Keys': [
                {'OrderID': 'order1'},
                {'OrderID': 'order2'}
            ]
        }
    }
)

users = response['Responses']['Users']
orders = response['Responses']['Orders']

# Handle unprocessed keys
while response.get('UnprocessedKeys'):
    response = dynamodb.batch_get_item(
        RequestItems=response['UnprocessedKeys']
    )
    users.extend(response['Responses'].get('Users', []))
    orders.extend(response['Responses'].get('Orders', []))
```

### BatchWriteItem

Write or delete up to 25 items in one or more tables.

**Characteristics**:
- Up to 25 put or delete requests
- Up to 16 MB of data
- Cannot update items (use UpdateItem instead)
- No conditional writes
- UnprocessedItems returned for retries

**Example**:
```python
with table.batch_writer() as batch:
    for i in range(100):
        batch.put_item(
            Item={
                'UserID': f'user{i}',
                'Name': f'User {i}',
                'Email': f'user{i}@example.com'
            }
        )

# Manual batch write with error handling
def batch_write_with_retry(items, table_name):
    request_items = {
        table_name: [
            {'PutRequest': {'Item': item}} for item in items
        ]
    }
    
    while request_items:
        response = dynamodb.batch_write_item(RequestItems=request_items)
        
        # Get unprocessed items for retry
        request_items = response.get('UnprocessedItems', {})
        
        if request_items:
            time.sleep(0.5)  # Backoff before retry
```

### Batch Best Practices

1. **Use batch_writer() helper**: Automatically handles batching and retries
2. **Handle unprocessed items**: Always check and retry
3. **Implement exponential backoff**: Avoid overwhelming the table
4. **Monitor capacity**: Each item consumes capacity individually
5. **Consider parallel batches**: For large datasets

---

## Streams

DynamoDB Streams capture item-level changes in your table.

### Stream Basics

**Characteristics**:
- Ordered record of item-level modifications
- Retention period: 24 hours
- Near real-time
- Exactly once delivery (within 24 hours)
- Sharded for parallel processing

### Stream View Types

1. **KEYS_ONLY**: Only the key attributes
2. **NEW_IMAGE**: The entire item after modification
3. **OLD_IMAGE**: The entire item before modification
4. **NEW_AND_OLD_IMAGES**: Both before and after

### Stream Record Structure

```json
{
  "eventID": "1",
  "eventName": "INSERT|MODIFY|REMOVE",
  "eventVersion": "1.1",
  "eventSource": "aws:dynamodb",
  "awsRegion": "us-east-1",
  "dynamodb": {
    "Keys": {
      "UserID": {"S": "user123"}
    },
    "NewImage": {
      "UserID": {"S": "user123"},
      "Name": {"S": "John Doe"},
      "Email": {"S": "john@example.com"}
    },
    "OldImage": {
      "UserID": {"S": "user123"},
      "Name": {"S": "John Smith"}
    },
    "SequenceNumber": "111",
    "SizeBytes": 26,
    "StreamViewType": "NEW_AND_OLD_IMAGES"
  },
  "eventSourceARN": "arn:aws:dynamodb:us-east-1:123456789012:table/Users/stream/2024-01-15T00:00:00.000"
}
```

### Stream Use Cases

#### 1. Replication and Backup
```python
def stream_to_s3(event, context):
    """Archive DynamoDB changes to S3"""
    for record in event['Records']:
        if record['eventName'] == 'INSERT' or record['eventName'] == 'MODIFY':
            new_image = record['dynamodb']['NewImage']
            # Convert to JSON and save to S3
            s3.put_object(
                Bucket='backup-bucket',
                Key=f"backups/{record['eventID']}.json",
                Body=json.dumps(new_image)
            )
```

#### 2. Materialized Views
```python
def update_materialized_view(event, context):
    """Update summary table based on changes"""
    for record in event['Records']:
        if record['eventName'] in ['INSERT', 'MODIFY']:
            new_image = record['dynamodb']['NewImage']
            # Update aggregated data in another table
            summary_table.update_item(
                Key={'Category': new_image['Category']['S']},
                UpdateExpression='ADD ItemCount :inc, TotalValue :value',
                ExpressionAttributeValues={
                    ':inc': 1,
                    ':value': Decimal(new_image['Price']['N'])
                }
            )
```

#### 3. Cross-Region Replication
```python
def replicate_to_region(event, context):
    """Replicate items to another region"""
    target_table = boto3.resource('dynamodb', region_name='eu-west-1').Table('Users')
    
    for record in event['Records']:
        if record['eventName'] == 'INSERT':
            item = record['dynamodb']['NewImage']
            target_table.put_item(Item=deserialize(item))
        elif record['eventName'] == 'MODIFY':
            item = record['dynamodb']['NewImage']
            target_table.put_item(Item=deserialize(item))
        elif record['eventName'] == 'REMOVE':
            keys = record['dynamodb']['Keys']
            target_table.delete_item(Key=deserialize(keys))
```

#### 4. Event-Driven Architecture
```python
def trigger_workflow(event, context):
    """Trigger workflows based on table changes"""
    for record in event['Records']:
        if record['eventName'] == 'INSERT':
            new_image = record['dynamodb']['NewImage']
            if new_image.get('Status', {}).get('S') == 'PENDING':
                # Send to SQS for processing
                sqs.send_message(
                    QueueUrl=queue_url,
                    MessageBody=json.dumps(new_image)
                )
            # Send notification
            sns.publish(
                TopicArn=topic_arn,
                Message=f"New order created: {new_image['OrderID']['S']}"
            )
```

### Terraform Configuration

```hcl
resource "aws_dynamodb_table" "with_streams" {
  name         = "OrdersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "OrderID"

  attribute {
    name = "OrderID"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

resource "aws_lambda_function" "stream_processor" {
  filename      = "lambda.zip"
  function_name = "process-dynamodb-stream"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
}

resource "aws_lambda_event_source_mapping" "stream_mapping" {
  event_source_arn  = aws_dynamodb_table.with_streams.stream_arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"

  # Optional: configure batch size and window
  batch_size                         = 100
  maximum_batching_window_in_seconds = 10
  parallelization_factor             = 10

  # Error handling
  maximum_retry_attempts = 3
  maximum_record_age_in_seconds = 604800  # 7 days

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.dlq.arn
    }
  }
}
```

---

## Global Tables

Multi-region, fully replicated tables for global applications.

### Characteristics

- **Multi-region replication**: Automatic replication across regions
- **Active-active**: Read and write in any region
- **Conflict resolution**: Last writer wins
- **Consistency**: Eventually consistent across regions
- **Version**: Use Version 2019.11.21 (latest)

### How It Works

1. Write to any region
2. DynamoDB replicates to all other regions
3. Typically replicates in under 1 second
4. Conflicts resolved using last-write-wins

### Prerequisites

- Tables must have same name in all regions
- Tables must have same primary key
- Tables must have streams enabled (NEW_AND_OLD_IMAGES)
- Tables must be empty before adding to global table

### Terraform Example

```hcl
# Primary region table
resource "aws_dynamodb_table" "global_table_us" {
  provider     = aws.us_east_1
  name         = "GlobalUsers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = "eu-west-1"
  }

  replica {
    region_name = "ap-southeast-1"
  }
}
```

### Conflict Resolution

DynamoDB uses last-writer-wins based on timestamp:

```python
# Write in us-east-1 at 10:00:00.000
table_us.put_item(Item={'UserID': 'user123', 'Name': 'John', 'UpdatedAt': '2024-01-15T10:00:00.000Z'})

# Write in eu-west-1 at 10:00:00.500
table_eu.put_item(Item={'UserID': 'user123', 'Name': 'Jane', 'UpdatedAt': '2024-01-15T10:00:00.500Z'})

# After replication, both regions will have:
# {'UserID': 'user123', 'Name': 'Jane', 'UpdatedAt': '2024-01-15T10:00:00.500Z'}
```

### Best Practices

1. **Include timestamps**: Track when items were modified
2. **Use version numbers**: Implement optimistic locking
3. **Design for conflicts**: Understand last-writer-wins behavior
4. **Monitor replication lag**: Use CloudWatch metrics
5. **Test failover**: Ensure application works in all regions

### Use Cases

- Multi-region SaaS applications
- Global e-commerce platforms
- Mobile apps with worldwide users
- Disaster recovery
- Data locality for compliance

---

## Point-in-Time Recovery

Continuous backups for DynamoDB tables.

### Characteristics

- **Retention**: 35 days
- **Recovery granularity**: Down to the second
- **Performance**: No impact on table performance
- **Restoration**: Creates new table from backup
- **Coverage**: Automatically backs up table and LSIs

### Enabling PITR

**Terraform**:
```hcl
resource "aws_dynamodb_table" "with_pitr" {
  name         = "UsersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
```

**AWS CLI**:
```bash
aws dynamodb update-continuous-backups \
    --table-name UsersTable \
    --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
```

### Restoring from PITR

```bash
# Restore to specific time
aws dynamodb restore-table-to-point-in-time \
    --source-table-name UsersTable \
    --target-table-name UsersTable-Restored \
    --restore-date-time "2024-01-15T10:00:00Z"

# Restore to latest restorable time
aws dynamodb restore-table-to-point-in-time \
    --source-table-name UsersTable \
    --target-table-name UsersTable-Restored \
    --use-latest-restorable-time
```

### On-Demand Backups

Manual backups that you create and manage.

**Characteristics**:
- Retained until explicitly deleted
- Full backup of table data and settings
- No performance impact
- Can restore to same or different region

**Terraform**:
```hcl
resource "aws_dynamodb_table" "main" {
  name         = "UsersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }
}

# Create backup (not directly supported in Terraform, use AWS CLI or Lambda)
```

**AWS CLI**:
```bash
# Create backup
aws dynamodb create-backup \
    --table-name UsersTable \
    --backup-name UsersTable-Backup-2024-01-15

# Restore from backup
aws dynamodb restore-table-from-backup \
    --target-table-name UsersTable-Restored \
    --backup-arn arn:aws:dynamodb:us-east-1:123456789012:table/UsersTable/backup/01234567890123-abcdefgh
```

---

## Encryption

DynamoDB provides encryption at rest and in transit.

### Encryption at Rest

All DynamoDB tables are encrypted at rest by default.

**Encryption Options**:

#### 1. AWS Owned CMK (Default)
- No additional cost
- Managed by AWS
- Cannot view or manage keys
- Simplest option

#### 2. AWS Managed CMK
- AWS managed in your account
- Visible in AWS KMS
- No additional KMS charges
- Cannot manage key rotation

#### 3. Customer Managed CMK
- Full control over key
- Can rotate, disable, set access policies
- Additional KMS charges apply
- Most flexible option

**Terraform Examples**:

```hcl
# Default encryption (AWS owned key)
resource "aws_dynamodb_table" "default_encryption" {
  name         = "UsersTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }
}

# Customer managed CMK
resource "aws_kms_key" "dynamodb_key" {
  description             = "DynamoDB encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_dynamodb_table" "cmk_encryption" {
  name         = "SecureTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserID"

  attribute {
    name = "UserID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }
}
```

### Encryption in Transit

All communication with DynamoDB is encrypted using TLS/SSL.

**Enforce TLS**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Principal": "*",
    "Action": "dynamodb:*",
    "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/*",
    "Condition": {
      "Bool": {
        "aws:SecureTransport": "false"
      }
    }
  }]
}
```

---

## Best Practices

### 1. Table Design

**Understand Access Patterns First**
```
Bad: Create table, then figure out queries
Good: List all queries, design table to support them
```

**Use Single Table Design for Related Data**
```
Benefits:
- Reduced costs (fewer tables)
- Better performance (fewer roundtrips)
- Atomic transactions across entity types

Example:
PK: USER#user123          SK: PROFILE
PK: USER#user123          SK: ORDER#order1
PK: USER#user123          SK: ORDER#order2
PK: PRODUCT#prod456       SK: DETAILS
```

**Avoid Hot Partitions**
```
Bad: Status as partition key (few values)
Good: UserID as partition key (high cardinality)

Bad: Date as partition key (recent dates get all traffic)
Good: UserID + Date composite key
```

### 2. Capacity Planning

**Use On-Demand for Unpredictable Workloads**
```
Good for:
- New applications
- Unpredictable traffic
- Spiky workloads

Not good for:
- Steady, predictable traffic (more expensive)
```

**Use Provisioned with Auto-Scaling for Predictable Workloads**
```
Benefits:
- Lower cost for steady traffic
- Predictable performance
- Reserved capacity discounts available

Configure:
- Set appropriate minimum capacity
- Set maximum capacity with buffer
- Target utilization: 70%
```

**Calculate Capacity Requirements**
```python
# Example calculation
item_size = 3  # KB
writes_per_second = 100
reads_per_second = 200

# Write capacity
wcu_needed = math.ceil(item_size / 1) * writes_per_second
# wcu_needed = 3 * 100 = 300 WCUs

# Read capacity (eventually consistent)
rcu_needed = math.ceil(item_size / 4) * reads_per_second / 2
# rcu_needed = 1 * 200 / 2 = 100 RCUs

# Read capacity (strongly consistent)
rcu_needed_strong = math.ceil(item_size / 4) * reads_per_second
# rcu_needed_strong = 1 * 200 = 200 RCUs
```

### 3. Query Optimization

**Prefer Query over Scan**
```python
# Bad: Scan entire table
response = table.scan(
    FilterExpression=Attr('UserID').eq('user123')
)

# Good: Query with partition key
response = table.query(
    KeyConditionExpression=Key('UserID').eq('user123')
)
```

**Use Sparse Indexes**
```python
# Only active users appear in index
if user_status == 'ACTIVE':
    item['ActiveUserIndex'] = 'ACTIVE'
    table.put_item(Item=item)

# Query only active users (smaller, faster)
response = table.query(
    IndexName='ActiveUserIndex',
    KeyConditionExpression=Key('ActiveUserIndex').eq('ACTIVE')
)
```

**Use Projection Expressions**
```python
# Bad: Retrieve all attributes
response = table.get_item(Key={'UserID': 'user123'})

# Good: Retrieve only needed attributes
response = table.get_item(
    Key={'UserID': 'user123'},
    ProjectionExpression='UserID, Name, Email'
)
```

### 4. Data Modeling

**Denormalize Data**
```python
# Bad: Relational approach requiring multiple queries
user = table.get_item(Key={'UserID': 'user123'})
orders = table.query(...)
products = table.batch_get_item(...)

# Good: Denormalized, single query
item = {
    'UserID': 'user123',
    'Name': 'John Doe',
    'RecentOrders': [
        {'OrderID': 'order1', 'Product': 'Widget', 'Amount': 29.99},
        {'OrderID': 'order2', 'Product': 'Gadget', 'Amount': 49.99}
    ]
}
```

**Use Composite Sort Keys**
```python
# Enables hierarchical queries
SK = f"{type}#{subtype}#{id}"

Examples:
SK: "ORDER#PENDING#order123"
SK: "ORDER#COMPLETED#order456"
SK: "MESSAGE#2024-01#msg789"

# Query all pending orders
response = table.query(
    KeyConditionExpression=Key('PK').eq('USER#user123') & 
                          Key('SK').begins_with('ORDER#PENDING')
)
```

**Implement Pagination**
```python
def get_all_items(user_id):
    items = []
    last_key = None
    
    while True:
        if last_key:
            response = table.query(
                KeyConditionExpression=Key('UserID').eq(user_id),
                ExclusiveStartKey=last_key
            )
        else:
            response = table.query(
                KeyConditionExpression=Key('UserID').eq(user_id)
            )
        
        items.extend(response['Items'])
        
        last_key = response.get('LastEvaluatedKey')
        if not last_key:
            break
    
    return items
```

### 5. Error Handling

**Implement Exponential Backoff**
```python
import time
from botocore.exceptions import ClientError

def put_item_with_retry(table, item, max_retries=5):
    for retry in range(max_retries):
        try:
            table.put_item(Item=item)
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == 'ProvisionedThroughputExceededException':
                if retry == max_retries - 1:
                    raise
                # Exponential backoff: 2^retry * 100ms
                time.sleep((2 ** retry) * 0.1)
            else:
                raise
    return False
```

**Handle Conditional Check Failures**
```python
try:
    table.update_item(
        Key={'UserID': 'user123'},
        UpdateExpression='SET Version = :new_version',
        ConditionExpression='Version = :expected_version',
        ExpressionAttributeValues={
            ':new_version': 2,
            ':expected_version': 1
        }
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
        # Handle version conflict
        print("Item was modified by another process")
        # Retry logic here
    else:
        raise
```

### 6. Security

**Use IAM Roles Instead of Access Keys**
```hcl
resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "lambda-dynamodb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_dynamodb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.main.arn
    }]
  })
}
```

**Implement Least Privilege Access**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/Users",
      "Condition": {
        "ForAllValues:StringEquals": {
          "dynamodb:LeadingKeys": ["${aws:username}"]
        }
      }
    }
  ]
}
```

**Use VPC Endpoints**
```hcl
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.dynamodb"
  
  route_table_ids = [aws_route_table.private.id]
  
  tags = {
    Name = "DynamoDB VPC Endpoint"
  }
}
```

### 7. Monitoring

**Key Metrics to Monitor**:

- **ConsumedReadCapacityUnits**: Read capacity consumed
- **ConsumedWriteCapacityUnits**: Write capacity consumed
- **UserErrors**: 4xx errors (client errors)
- **SystemErrors**: 5xx errors (server errors)
- **ThrottledRequests**: Requests exceeding capacity
- **ConditionalCheckFailedRequests**: Failed conditional operations

**CloudWatch Alarms**:
```hcl
resource "aws_cloudwatch_metric_alarm" "throttled_requests" {
  alarm_name          = "dynamodb-throttled-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB throttled requests"
  
  dimensions = {
    TableName = aws_dynamodb_table.main.name
  }
}
```

---

## Performance Optimization

### 1. Partition Key Distribution

**Problem**: Hot partitions cause throttling
**Solution**: Distribute requests evenly

```python
# Bad: Date as partition key (recent dates get most traffic)
PK = "2024-01-15"

# Good: Add randomness
import random
shard = random.randint(0, 9)
PK = f"2024-01-15#{shard}"

# Query all shards
all_items = []
for shard in range(10):
    items = table.query(
        KeyConditionExpression=Key('Date').eq(f'2024-01-15#{shard}')
    )
    all_items.extend(items['Items'])
```

### 2. Burst Capacity

DynamoDB provides burst capacity:
- Accumulates unused capacity (up to 5 minutes)
- Use for occasional spikes
- Not guaranteed, don't rely on it

### 3. Parallel Scans

For large table scans, use parallel segments:

```python
from concurrent.futures import ThreadPoolExecutor

def scan_segment(segment, total_segments):
    paginator = dynamodb.meta.client.get_paginator('scan')
    
    items = []
    for page in paginator.paginate(
        TableName='LargeTable',
        Segment=segment,
        TotalSegments=total_segments
    ):
        items.extend(page['Items'])
    
    return items

# Scan with 10 parallel segments
with ThreadPoolExecutor(max_workers=10) as executor:
    futures = [executor.submit(scan_segment, i, 10) for i in range(10)]
    all_items = []
    for future in futures:
        all_items.extend(future.result())
```

### 4. Caching Strategies

**DynamoDB Accelerator (DAX)**:
```hcl
resource "aws_dax_cluster" "main" {
  cluster_name       = "my-dax-cluster"
  iam_role_arn       = aws_iam_role.dax.arn
  node_type          = "dax.t3.small"
  replication_factor = 3

  subnet_group_name = aws_dax_subnet_group.main.name
  security_group_ids = [aws_security_group.dax.id]
}

resource "aws_dax_subnet_group" "main" {
  name       = "my-dax-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}
```

**Application-Level Caching**:
```python
import redis
import json

cache = redis.Redis(host='localhost', port=6379)

def get_item_cached(user_id):
    # Try cache first
    cached = cache.get(f'user:{user_id}')
    if cached:
        return json.loads(cached)
    
    # Cache miss, query DynamoDB
    response = table.get_item(Key={'UserID': user_id})
    item = response.get('Item')
    
    if item:
        # Cache for 5 minutes
        cache.setex(f'user:{user_id}', 300, json.dumps(item))
    
    return item
```

### 5. Batch Operations

Use batch operations when possible:

```python
# Bad: Individual writes
for item in items:
    table.put_item(Item=item)  # 100 requests

# Good: Batch writes
with table.batch_writer() as batch:
    for item in items:
        batch.put_item(Item=item)  # 4 requests (25 items each)
```

---

## Cost Optimization

### 1. Choose the Right Capacity Mode

**On-Demand**: 
- Unpredictable workloads
- New applications
- Cost: ~5x more per request than provisioned

**Provisioned**:
- Predictable workloads
- Cost-effective for steady traffic
- Can use reserved capacity for additional savings

**Cost Comparison Example**:
```
Workload: 1 million reads/day, 100K writes/day
Average item size: 4 KB

On-Demand:
- Reads: 1,000,000 * $0.25/million = $0.25
- Writes: 100,000 * $1.25/million = $0.125
- Total: $0.375/day = $11.25/month

Provisioned (with auto-scaling):
- Avg RCUs: 12 (1M reads / 86400 seconds)
- Avg WCUs: 2 (100K writes / 86400 seconds)
- Cost: (12 + 2) * $0.00065/hour * 730 hours = $6.64/month

Savings: 41% with provisioned mode
```

### 2. Optimize Index Usage

**Only create needed indexes**:
```python
# Bad: Create index "just in case"
# Each GSI costs same as base table

# Good: Only create indexes for known access patterns
# Consider if query can use base table instead
```

**Choose appropriate projections**:
```python
# Bad: Project ALL attributes (highest cost)
projection_type = 'ALL'

# Good: Project only needed attributes
projection_type = 'INCLUDE'
non_key_attributes = ['Name', 'Email']  # Only what queries need

# Best: Project only keys (lowest cost)
projection_type = 'KEYS_ONLY'
```

### 3. Manage Item Size

**Stay under 1 KB for writes**:
```python
# Each 1 KB = 1 WCU
item_size = 0.5  # KB
wcu_per_write = 1

item_size = 3  # KB
wcu_per_write = 3  # 3x cost!
```

**Compress large attributes**:
```python
import gzip
import base64

def compress_data(data):
    compressed = gzip.compress(data.encode())
    return base64.b64encode(compressed).decode()

def decompress_data(compressed):
    decoded = base64.b64decode(compressed.encode())
    return gzip.decompress(decoded).decode()

# Store compressed
item = {
    'ID': 'doc123',
    'Content': compress_data(large_document)  # Reduce item size
}
```

### 4. Use TTL for Automatic Cleanup

```hcl
resource "aws_dynamodb_table" "with_ttl" {
  name         = "SessionsTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SessionID"

  attribute {
    name = "SessionID"
    type = "S"
  }

  ttl {
    attribute_name = "ExpirationTime"
    enabled        = true
  }
}
```

```python
import time

# Set TTL for 24 hours from now
expiration_time = int(time.time()) + 86400

table.put_item(
    Item={
        'SessionID': 'session123',
        'Data': 'session data',
        'ExpirationTime': expiration_time  # Automatically deleted after this time
    }
)
```

### 5. Monitor and Right-Size Capacity

```python
# CloudWatch metrics to monitor:
- ConsumedReadCapacityUnits
- ConsumedWriteCapacityUnits
- ProvisionedReadCapacityUnits
- ProvisionedWriteCapacityUnits

# If consumed consistently < 70% of provisioned, reduce capacity
# If throttling occurs, increase capacity or enable auto-scaling
```

---

## Terraform Examples

### Complete Table with All Features

```hcl
# KMS key for encryption
resource "aws_kms_key" "dynamodb" {
  description             = "DynamoDB table encryption key"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/dynamodb-table-key"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# Main table
resource "aws_dynamodb_table" "complete_example" {
  name           = "CompleteExampleTable"
  billing_mode   = "PROVISIONED"
  read_capacity  = 10
  write_capacity = 10
  hash_key       = "PK"
  range_key      = "SK"

  # Attributes
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  attribute {
    name = "LSI1SK"
    type = "S"
  }

  # Global Secondary Index
  global_secondary_index {
    name               = "GSI1"
    hash_key           = "GSI1PK"
    range_key          = "GSI1SK"
    write_capacity     = 5
    read_capacity      = 5
    projection_type    = "INCLUDE"
    non_key_attributes = ["Name", "Email"]
  }

  # Local Secondary Index
  local_secondary_index {
    name            = "LSI1"
    range_key       = "LSI1SK"
    projection_type = "ALL"
  }

  # TTL
  ttl {
    attribute_name = "ExpirationTime"
    enabled        = true
  }

  # Streams
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  # Tags
  tags = {
    Environment = "production"
    Application = "my-app"
  }
}

# Auto-scaling for read capacity
resource "aws_appautoscaling_target" "read_target" {
  max_capacity       = 100
  min_capacity       = 10
  resource_id        = "table/${aws_dynamodb_table.complete_example.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.read_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70.0
  }
}

# Auto-scaling for write capacity
resource "aws_appautoscaling_target" "write_target" {
  max_capacity       = 100
  min_capacity       = 10
  resource_id        = "table/${aws_dynamodb_table.complete_example.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.write_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.write_target.resource_id
  scalable_dimension = aws_appautoscaling_target.write_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.write_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70.0
  }
}

# IAM role for Lambda to access DynamoDB
resource "aws_iam_role" "lambda_dynamodb" {
  name = "lambda-dynamodb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_dynamodb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = [
          aws_dynamodb_table.complete_example.arn,
          "${aws_dynamodb_table.complete_example.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ]
        Resource = aws_dynamodb_table.complete_example.stream_arn
      }
    ]
  })
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  alarm_name          = "${aws_dynamodb_table.complete_example.name}-read-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB read throttle events"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.complete_example.name
  }
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  alarm_name          = "${aws_dynamodb_table.complete_example.name}-write-throttle"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB write throttle events"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.complete_example.name
  }
}
```

### Multi-Region Global Table

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider for us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Provider for eu-west-1
provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

# Global table in us-east-1
resource "aws_dynamodb_table" "global_table" {
  provider         = aws.us_east_1
  name             = "GlobalUsersTable"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "UserID"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "UserID"
    type = "S"
  }

  replica {
    region_name = "eu-west-1"
  }

  replica {
    region_name = "ap-southeast-1"
  }

  tags = {
    Environment = "production"
    GlobalTable = "true"
  }
}
```

---

## Advanced Patterns

### 1. Single Table Design

Store multiple entity types in one table using generic attribute names.

```python
# Entity structure
entities = {
    'User': {
        'PK': 'USER#user123',
        'SK': 'PROFILE',
        'Type': 'User',
        'Name': 'John Doe',
        'Email': 'john@example.com'
    },
    'Order': {
        'PK': 'USER#user123',
        'SK': 'ORDER#2024-01-15#order456',
        'Type': 'Order',
        'OrderID': 'order456',
        'Amount': 99.99,
        'Status': 'COMPLETED'
    },
    'Product': {
        'PK': 'PRODUCT#prod789',
        'SK': 'DETAILS',
        'Type': 'Product',
        'Name': 'Widget',
        'Price': 29.99,
        'Stock': 100
    }
}

# Access patterns
# 1. Get user profile
response = table.get_item(
    Key={'PK': 'USER#user123', 'SK': 'PROFILE'}
)

# 2. Get all orders for a user
response = table.query(
    KeyConditionExpression=Key('PK').eq('USER#user123') & 
                          Key('SK').begins_with('ORDER#')
)

# 3. Get orders within date range
response = table.query(
    KeyConditionExpression=Key('PK').eq('USER#user123') & 
                          Key('SK').between('ORDER#2024-01-01', 'ORDER#2024-12-31')
)
```

**GSI for Inverted Index**:
```python
# GSI1: Inverted index
GSI1PK = SK  # What was the sort key becomes partition key
GSI1SK = PK  # What was the partition key becomes sort key

# Example: Find all users who ordered a product
# Base table: PK=USER#user123, SK=ORDER#order456, ProductID=prod789
# GSI1: GSI1PK=ORDER#order456, GSI1SK=USER#user123

response = table.query(
    IndexName='GSI1',
    KeyConditionExpression=Key('GSI1PK').begins_with('ORDER#')
)
```

### 2. Adjacency List Pattern

Model many-to-many relationships.

```python
# Social network example
items = [
    # User follows user
    {'PK': 'USER#alice', 'SK': 'FOLLOWS#bob', 'Type': 'Follow'},
    {'PK': 'USER#alice', 'SK': 'FOLLOWS#charlie', 'Type': 'Follow'},
    
    # User is followed by user (denormalized for easy queries)
    {'PK': 'USER#bob', 'SK': 'FOLLOWER#alice', 'Type': 'Follower'},
    {'PK': 'USER#charlie', 'SK': 'FOLLOWER#alice', 'Type': 'Follower'},
    
    # User profile
    {'PK': 'USER#alice', 'SK': 'PROFILE', 'Name': 'Alice', 'Email': 'alice@example.com'}
]

# Queries
# Get all users that Alice follows
following = table.query(
    KeyConditionExpression=Key('PK').eq('USER#alice') & 
                          Key('SK').begins_with('FOLLOWS#')
)

# Get all followers of Bob
followers = table.query(
    KeyConditionExpression=Key('PK').eq('USER#bob') & 
                          Key('SK').begins_with('FOLLOWER#')
)
```

### 3. Composite Sort Key Pattern

Create hierarchical data with queryable levels.

```python
# E-commerce hierarchy: Country > State > City > Store

items = [
    {
        'PK': 'SALES',
        'SK': 'USA#CA#SanFrancisco#Store1',
        'Revenue': 10000,
        'Date': '2024-01-15'
    },
    {
        'PK': 'SALES',
        'SK': 'USA#CA#LosAngeles#Store2',
        'Revenue': 15000,
        'Date': '2024-01-15'
    },
    {
        'PK': 'SALES',
        'SK': 'USA#NY#NewYork#Store3',
        'Revenue': 20000,
        'Date': '2024-01-15'
    }
]

# Query all stores in California
ca_stores = table.query(
    KeyConditionExpression=Key('PK').eq('SALES') & 
                          Key('SK').begins_with('USA#CA#')
)

# Query specific city
sf_stores = table.query(
    KeyConditionExpression=Key('PK').eq('SALES') & 
                          Key('SK').begins_with('USA#CA#SanFrancisco#')
)

# Query specific store
store_data = table.query(
    KeyConditionExpression=Key('PK').eq('SALES') & 
                          Key('SK').eq('USA#CA#SanFrancisco#Store1')
)
```

### 4. Write Sharding for Hot Partitions

Distribute writes across multiple partition keys.

```python
import random
import hashlib

def get_shard_id(item_id, num_shards=10):
    """Deterministic shard selection"""
    hash_value = int(hashlib.md5(item_id.encode()).hexdigest(), 16)
    return hash_value % num_shards

# Write with shard
item_id = 'item123'
shard_id = get_shard_id(item_id)

table.put_item(
    Item={
        'PK': f'ITEM#{shard_id}',
        'SK': f'ITEM#{item_id}',
        'Data': 'item data'
    }
)

# Query across all shards
def query_all_shards(item_id, num_shards=10):
    all_items = []
    
    for shard in range(num_shards):
        response = table.query(
            KeyConditionExpression=Key('PK').eq(f'ITEM#{shard}') & 
                                  Key('SK').eq(f'ITEM#{item_id}')
        )
        all_items.extend(response['Items'])
    
    return all_items
```

### 5. Time-Series Data Pattern

Efficiently store and query time-series data.

```python
from datetime import datetime, timedelta

# Use date buckets to prevent partition from growing too large
def get_date_bucket(timestamp, bucket_size_days=30):
    """Group data into time buckets"""
    dt = datetime.fromisoformat(timestamp)
    bucket_start = dt.replace(day=1)  # Start of month
    return bucket_start.strftime('%Y-%m')

# Store sensor data
timestamp = '2024-01-15T10:30:00Z'
bucket = get_date_bucket(timestamp)

table.put_item(
    Item={
        'PK': f'SENSOR#sensor123',
        'SK': f'{bucket}#{timestamp}',
        'Temperature': 72.5,
        'Humidity': 45.2
    }
)

# Query data for a month
response = table.query(
    KeyConditionExpression=Key('PK').eq('SENSOR#sensor123') & 
                          Key('SK').begins_with('2024-01#')
)

# Query data for a specific time range
response = table.query(
    KeyConditionExpression=Key('PK').eq('SENSOR#sensor123') & 
                          Key('SK').between(
                              '2024-01#2024-01-15T00:00:00Z',
                              '2024-01#2024-01-15T23:59:59Z'
                          )
)
```

### 6. Materialized Aggregation Pattern

Pre-compute aggregations for fast queries.

```python
# Update both detail and aggregate in transaction
def record_sale(product_id, amount, date):
    """Record sale and update daily aggregate"""
    
    sale_id = str(uuid.uuid4())
    
    dynamodb.meta.client.transact_write_items(
        TransactItems=[
            # Record individual sale
            {
                'Put': {
                    'TableName': 'Sales',
                    'Item': {
                        'PK': {'S': f'PRODUCT#{product_id}'},
                        'SK': {'S': f'SALE#{date}#{sale_id}'},
                        'Amount': {'N': str(amount)}
                    }
                }
            },
            # Update daily aggregate
            {
                'Update': {
                    'TableName': 'Sales',
                    'Key': {
                        'PK': {'S': f'PRODUCT#{product_id}'},
                        'SK': {'S': f'AGGREGATE#{date}'}
                    },
                    'UpdateExpression': 'ADD TotalSales :amount, SaleCount :one',
                    'ExpressionAttributeValues': {
                        ':amount': {'N': str(amount)},
                        ':one': {'N': '1'}
                    }
                }
            }
        ]
    )

# Query aggregate (fast, single item)
response = table.get_item(
    Key={
        'PK': 'PRODUCT#prod123',
        'SK': 'AGGREGATE#2024-01-15'
    }
)
# Returns: {'TotalSales': 50000, 'SaleCount': 100}
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. ProvisionedThroughputExceededException

**Cause**: Requests exceed provisioned capacity or on-demand limits

**Solutions**:
```python
# Enable auto-scaling (for provisioned mode)
# Or switch to on-demand mode
# Or implement exponential backoff

import time
from botocore.exceptions import ClientError

def retry_with_backoff(func, max_retries=5):
    for retry in range(max_retries):
        try:
            return func()
        except ClientError as e:
            if e.response['Error']['Code'] == 'ProvisionedThroughputExceededException':
                if retry == max_retries - 1:
                    raise
                wait_time = (2 ** retry) * 0.1
                time.sleep(wait_time)
            else:
                raise
```

#### 2. ConditionalCheckFailedException

**Cause**: Condition expression evaluates to false

**Solutions**:
```python
# Implement optimistic locking correctly
# Handle conflicts gracefully

try:
    table.update_item(
        Key={'ID': 'item123'},
        UpdateExpression='SET #data = :data, Version = :new_version',
        ConditionExpression='Version = :current_version',
        ExpressionAttributeNames={'#data': 'Data'},
        ExpressionAttributeValues={
            ':data': new_data,
            ':current_version': current_version,
            ':new_version': current_version + 1
        }
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
        # Reload item and retry
        response = table.get_item(Key={'ID': 'item123'})
        current_version = response['Item']['Version']
        # Retry logic here
```

#### 3. ItemSizeTooLarge

**Cause**: Item exceeds 400 KB limit

**Solutions**:
```python
# 1. Compress large attributes
import gzip
import base64

compressed = base64.b64encode(gzip.compress(large_data.encode())).decode()

# 2. Store large data in S3, reference in DynamoDB
s3_key = f'data/{item_id}'
s3.put_object(Bucket='my-bucket', Key=s3_key, Body=large_data)

table.put_item(
    Item={
        'ID': item_id,
        'S3Reference': s3_key
    }
)

# 3. Split into multiple items
for i, chunk in enumerate(chunks(large_data, chunk_size)):
    table.put_item(
        Item={
            'PK': item_id,
            'SK': f'CHUNK#{i}',
            'Data': chunk
        }
    )
```

#### 4. Hot Partitions

**Cause**: Uneven distribution of requests across partitions

**Diagnosis**:
```python
# Check CloudWatch metrics
# ConsumedReadCapacityUnits per partition
# ConsumedWriteCapacityUnits per partition
# Look for spikes in specific partitions
```

**Solutions**:
```python
# 1. Use better partition key (high cardinality)
# Bad: Status (few values)
# Good: UserID (many values)

# 2. Add write sharding
shard_id = hash(key) % num_shards
PK = f'{key}#{shard_id}'

# 3. Use burst capacity wisely
# Accumulates for up to 5 minutes
# Good for occasional spikes

# 4. Consider DAX for read-heavy workloads
```

#### 5. Query Returns Empty Results

**Possible Causes**:
1. Wrong key values
2. Eventually consistent read (data not yet propagated)
3. Item doesn't exist
4. FilterExpression too restrictive

**Debugging**:
```python
# 1. Verify key values
print(f"Querying with PK: {pk_value}, SK: {sk_value}")

# 2. Use strongly consistent read
response = table.query(
    KeyConditionExpression=Key('PK').eq(pk_value),
    ConsistentRead=True
)

# 3. Check if items exist
response = table.scan(
    FilterExpression=Attr('PK').eq(pk_value)
)

# 4. Remove FilterExpression temporarily
response = table.query(
    KeyConditionExpression=Key('PK').eq(pk_value)
    # FilterExpression removed for debugging
)
```

#### 6. High Costs

**Analysis**:
```python
# 1. Check capacity mode
# On-demand vs Provisioned

# 2. Review index projections
# ALL vs INCLUDE vs KEYS_ONLY

# 3. Monitor storage
# Base table + indexes
# Consider removing unused indexes

# 4. Check for unnecessary scans
# Prefer Query over Scan

# 5. Review on-demand request counts
# CloudWatch: UserRequests metric
```

**Optimization**:
```python
# 1. Switch to provisioned mode if traffic is steady
# 2. Right-size provisioned capacity
# 3. Use reserved capacity for additional savings
# 4. Optimize index projections
# 5. Implement TTL to remove old data
# 6. Consider table archival to S3 for old data
```

---

## Quick Reference

### Key Limits

| Limit | Value |
|-------|-------|
| Item size | 400 KB |
| Query result size | 1 MB |
| Scan result size | 1 MB |
| Transaction items | 100 |
| Batch get items | 100 |
| Batch write items | 25 |
| GSIs per table | 20 |
| LSIs per table | 5 |
| Attribute name length | 64 KB |
| Partition key length | 2048 bytes |
| Sort key length | 1024 bytes |
| String attribute | 400 KB |
| Number precision | 38 digits |
| Nested depth | 32 levels |

### Capacity Units

```
Read Capacity Unit (RCU):
- 1 strongly consistent read/sec for items up to 4 KB
- 2 eventually consistent reads/sec for items up to 4 KB

Write Capacity Unit (WCU):
- 1 write/sec for items up to 1 KB

Transactional operations consume 2x capacity
```

### Common Boto3 Operations

```python
import boto3
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('TableName')

# Create item
table.put_item(Item={'PK': 'value', 'SK': 'value', 'Data': 'data'})

# Read item
response = table.get_item(Key={'PK': 'value', 'SK': 'value'})

# Update item
table.update_item(
    Key={'PK': 'value'},
    UpdateExpression='SET #attr = :val',
    ExpressionAttributeNames={'#attr': 'AttributeName'},
    ExpressionAttributeValues={':val': 'new value'}
)

# Delete item
table.delete_item(Key={'PK': 'value'})

# Query
response = table.query(
    KeyConditionExpression=Key('PK').eq('value') & Key('SK').begins_with('prefix')
)

# Scan
response = table.scan(FilterExpression=Attr('Status').eq('ACTIVE'))

# Batch write
with table.batch_writer() as batch:
    batch.put_item(Item={'PK': 'value1'})
    batch.put_item(Item={'PK': 'value2'})
```

### Expression Attribute Syntax

```python
# Reserved words require attribute names
ExpressionAttributeNames = {'#name': 'Name'}  # 'Name' is reserved

# Values always use attribute values
ExpressionAttributeValues = {':val': 'value'}

# Update expressions
UpdateExpression = 'SET #name = :val, Count = Count + :inc REMOVE OldAttr'

# Condition expressions
ConditionExpression = '#name = :val AND Count > :min'

# Filter expressions
FilterExpression = Attr('Status').eq('ACTIVE') & Attr('Count').gt(10)
```

---

## Additional Resources

### Official Documentation
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)
- [Boto3 DynamoDB Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb.html)
- [Terraform AWS Provider - DynamoDB](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table)

### Best Practice Guides
- [Best Practices for DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [DynamoDB Table Design](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-general-nosql-design.html)
- [NoSQL Design for DynamoDB](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-modeling-nosql.html)

### Tools
- [NoSQL Workbench](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/workbench.html) - Data modeling and visualization
- [DynamoDB Local](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DynamoDBLocal.html) - Local development version
- [AWS CLI DynamoDB Commands](https://docs.aws.amazon.com/cli/latest/reference/dynamodb/)

---

## Conclusion

This reference guide covers the essential concepts, operations, and best practices for working with DynamoDB. Key takeaways:

1. **Design for Access Patterns**: Always start with your queries
2. **Choose the Right Keys**: Partition key for distribution, sort key for ordering
3. **Use Indexes Wisely**: GSIs for alternate access patterns, LSIs for alternate sort orders
4. **Optimize Costs**: Choose appropriate capacity mode and projections
5. **Monitor Performance**: Watch for throttling and hot partitions
6. **Implement Error Handling**: Use exponential backoff and handle conflicts
7. **Consider Single Table Design**: For complex applications with many entity types

Remember: DynamoDB is not a relational database. Embrace denormalization, pre-compute aggregations, and design for your specific access patterns.