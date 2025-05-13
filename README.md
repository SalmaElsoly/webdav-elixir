# WebDAV Server

A WebDAV server implementation in Elixir supporting standard WebDAV operations including file locking.

## Features

- Basic WebDAV operations (GET, PUT, DELETE, MKCOL)
- Property management (PROPFIND, PROPPATCH)
- Resource locking (LOCK, UNLOCK)
- Copy and Move operations (COPY, MOVE)
- Support for file and directory operations
- Recursive operations with depth control
- Lock-aware operations
- Custom property support

## Prerequisites

- Elixir ~> 1.17
- Erlang/OTP ~> 27.0
- Mix (Elixir's build tool)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/SalmaElsoly/webdav-elixir.git
cd webdav-elixir
```

2. Install dependencies:
```bash
mix deps.get
```

3. Compile the project:
```bash
mix compile
```

## Running the Server

Start the WebDAV server using Mix:

```bash
# Start with default storage path (./storage)
mix run --no-halt

# Start with custom storage path
mix run --no-halt -- --storage-path /path/to/storage
```

The server will start on port 8080 by default.

## Usage

#### Basic File Operations

```bash
# Create/Upload a file
curl -X PUT -d "Hello WebDAV" http://localhost:8080/webdav/test.txt

# Download a file
curl -X GET http://localhost:8080/webdav/test.txt

# Delete a file
curl -X DELETE http://localhost:8080/webdav/test.txt

# Create a directory
curl -X MKCOL http://localhost:8080/webdav/testdir
```

#### Lock Operations

```bash
# Lock a file
curl -X LOCK -H "Timeout: Second-3600" -H "Depth: 0" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner>
    <D:href>mailto:user@example.com</D:href>
  </D:owner>
</D:lockinfo>' \
  http://localhost:8080/webdav/test.txt

# Modify a locked file (using lock token)
curl -X PUT -H "If: <lock-token>" -d "New content" http://localhost:8080/webdav/test.txt

# Unlock a file
curl -X UNLOCK -H "Lock-Token: <lock-token>" http://localhost:8080/webdav/test.txt
```

#### Property Operations

```bash
# Get properties
curl -X PROPFIND -H "Depth: 0" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
</D:propfind>' \
  http://localhost:8080/webdav/test.txt

# Set custom property
curl -X PROPPATCH -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:propertyupdate xmlns:D="DAV:">
  <D:set>
    <D:prop>
      <D:custom-property>custom value</D:custom-property>
    </D:prop>
  </D:set>
</D:propertyupdate>' \
  http://localhost:8080/webdav/test.txt
```

#### Copy and Move Operations

```bash
# Copy a file
curl -X COPY -H "Destination: http://localhost:8080/webdav/test_copy.txt" \
  http://localhost:8080/webdav/test.txt

# Move a file
curl -X MOVE -H "Destination: http://localhost:8080/webdav/test_moved.txt" \
  http://localhost:8080/webdav/test.txt
```
