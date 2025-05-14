# WebDAV Server Test Commands

This document contains curl commands for testing the WebDAV server running on port 8080.

## Basic File Operations

### Create a file

```bash
curl -X PUT -d "Hello WebDAV World" http://localhost:8080/webdav/test.txt
```

### Get a file

```bash
curl -X GET http://localhost:8080/webdav/test.txt
```

### Delete a file

```bash
curl -X DELETE http://localhost:8080/webdav/test.txt
```

### Create a directory

```bash
curl -X MKCOL http://localhost:8080/webdav/testdir
```

## PROPFIND Requests

### List directory contents (Depth: 1)

```bash
curl -X PROPFIND -H "Depth: 1" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:resourcetype/>
    <D:getcontentlength/>
    <D:getlastmodified/>
    <D:creationdate/>
  </D:prop>
</D:propfind>' \
  http://localhost:8080/webdav/
```

### Get specific properties

```bash
curl -X PROPFIND -H "Depth: 0" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:getcontentlength/>
    <D:getcontenttype/>
  </D:prop>
</D:propfind>' \
  http://localhost:8080/webdav/test.txt
```

### Get all properties with allprop

```bash
curl -X PROPFIND -H "Depth: 0" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:allprop/>
</D:propfind>' \
  http://localhost:8080/webdav/test.txt
```

## PROPPATCH Requests

### Set a custom property

```bash
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

### Remove a custom property

```bash
curl -X PROPPATCH -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:propertyupdate xmlns:D="DAV:">
  <D:remove>
    <D:prop>
      <D:custom-property/>
    </D:prop>
  </D:remove>
</D:propertyupdate>' \
  http://localhost:8080/webdav/test.txt
```

## Lock Operations

### Lock a file (exclusive write lock)

```bash
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
```

### Lock a directory and all descendants (infinite depth)

```bash
curl -X LOCK -H "Timeout: Second-3600" -H "Depth: infinity" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner>
    <D:href>mailto:user@example.com</D:href>
  </D:owner>
</D:lockinfo>' \
  http://localhost:8080/webdav/testdir
```

### Try to modify a locked file (should fail)

```bash
curl -X PUT -d "New content" http://localhost:8080/webdav/test.txt
```

### Modify a locked file with lock token

```bash
# Replace <lock-token> with the actual lock token received from LOCK request
curl -X PUT -H "If: <lock-token>" -d "New content" http://localhost:8080/webdav/test.txt
```

### Unlock a file

```bash
# Replace <lock-token> with the actual lock token received from LOCK request
curl -X UNLOCK -H "If: <lock-token>" http://localhost:8080/webdav/test.txt
```

## Move and Copy Operations

### Copy a file

```bash
curl -X COPY -H "Destination: http://localhost:8080/webdav/test_copy.txt" \
  http://localhost:8080/webdav/test.txt
```

### Copy a locked file (should fail)

```bash
curl -X COPY -H "Destination: http://localhost:8080/webdav/test_copy.txt" \
  http://localhost:8080/webdav/test.txt
```

### Copy a locked file with lock token

```bash
# Replace <lock-token> with the actual lock token
curl -X COPY -H "If: <lock-token>" \
  -H "Destination: http://localhost:8080/webdav/test_copy.txt" \
  http://localhost:8080/webdav/test.txt
```

### Move a file

```bash
curl -X MOVE -H "Destination: http://localhost:8080/webdav/test_moved.txt" \
  http://localhost:8080/webdav/test.txt
```

### Move a locked file (should fail)

```bash
curl -X MOVE -H "Destination: http://localhost:8080/webdav/test_moved.txt" \
  http://localhost:8080/webdav/test.txt
```

### Move a locked file with lock token

```bash
# Replace <lock-token> with the actual lock token
curl -X MOVE -H "If: <lock-token>" \
  -H "Destination: http://localhost:8080/webdav/test_moved.txt" \
  http://localhost:8080/webdav/test.txt
```

### Copy a directory (Depth: infinity)

```bash
curl -X COPY -H "Depth: infinity" \
  -H "Destination: http://localhost:8080/webdav/testdir_copy" \
  http://localhost:8080/webdav/testdir
```

### Move a directory

```bash
curl -X MOVE -H "Destination: http://localhost:8080/webdav/testdir_moved" \
  http://localhost:8080/webdav/testdir
```

## Error Cases Tests

### 404 Not Found (Non-existent resource)

```bash
curl -X GET http://localhost:8080/webdav/nonexistent.txt
```

### 409 Conflict (Creating a directory where parent doesn't exist)

```bash
curl -X MKCOL http://localhost:8080/webdav/nonexistent/subdir
```

### 423 Locked (Attempt to modify locked resource)

```bash
curl -X PUT -d "New content" http://localhost:8080/webdav/locked.txt
```

### 412 Precondition Failed (COPY/MOVE without Destination header)

```bash
curl -X COPY http://localhost:8080/webdav/test.txt
```

## Complete Test Sequences

### Lock and Modification Sequence

```bash
# 1. Create a test file
curl -X PUT -d "Initial content" http://localhost:8080/webdav/locktest.txt

# 2. Lock the file
curl -X LOCK -H "Timeout: Second-3600" -H "Depth: 0" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner>
    <D:href>mailto:user@example.com</D:href>
  </D:owner>
</D:lockinfo>' \
  http://localhost:8080/webdav/locktest.txt

# 3. Try to modify without lock token (should fail)
curl -X PUT -d "New content" http://localhost:8080/webdav/locktest.txt

# 4. Modify with lock token
curl -X PUT -H "If: <lock-token>" -d "New content" http://localhost:8080/webdav/locktest.txt

# 5. Unlock the file
curl -X UNLOCK -H "Lock-Token: <lock-token>" http://localhost:8080/webdav/locktest.txt

# 6. Verify modification is possible after unlock
curl -X PUT -d "Final content" http://localhost:8080/webdav/locktest.txt

# 7. Clean up
curl -X DELETE http://localhost:8080/webdav/locktest.txt
```

### Directory Operations with Locks

```bash
# 1. Create a directory
curl -X MKCOL http://localhost:8080/webdav/lockdir

# 2. Create some files in the directory
curl -X PUT -d "File 1" http://localhost:8080/webdav/lockdir/file1.txt
curl -X PUT -d "File 2" http://localhost:8080/webdav/lockdir/file2.txt

# 3. Lock the directory with infinite depth
curl -X LOCK -H "Timeout: Second-3600" -H "Depth: infinity" -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="utf-8" ?>
<D:lockinfo xmlns:D="DAV:">
  <D:lockscope><D:exclusive/></D:lockscope>
  <D:locktype><D:write/></D:locktype>
  <D:owner>
    <D:href>mailto:user@example.com</D:href>
  </D:owner>
</D:lockinfo>' \
  http://localhost:8080/webdav/lockdir

# 4. Try to modify a file in the directory (should fail)
curl -X PUT -d "New content" http://localhost:8080/webdav/lockdir/file1.txt

# 5. Try to add a new file (should fail)
curl -X PUT -d "New file" http://localhost:8080/webdav/lockdir/file3.txt

# 6. Try to move the directory (should fail)
curl -X MOVE -H "Destination: http://localhost:8080/webdav/lockdir_moved" \
  http://localhost:8080/webdav/lockdir

# 7. Move with lock token
curl -X MOVE -H "If: <lock-token>" \
  -H "Destination: http://localhost:8080/webdav/lockdir_moved" \
  http://localhost:8080/webdav/lockdir

# 8. Unlock the directory
curl -X UNLOCK -H "Lock-Token: <lock-token>" http://localhost:8080/webdav/lockdir_moved

# 9. Clean up
curl -X DELETE http://localhost:8080/webdav/lockdir_moved
```

## Debugging Tips

1. Use the `-v` (verbose) flag with curl to see request/response headers and status codes:

   ```bash
   curl -v -X PROPFIND -H "Depth: 0" http://localhost:8080/webdav/test.txt
   ```

2. For XML responses, pipe the output to xmllint for pretty-printing (if available):

   ```bash
   curl -X PROPFIND -H "Depth: 0" http://localhost:8080/webdav/test.txt | xmllint --format -
   ```

3. Check the server logs for detailed error information if the curl response doesn't provide enough info.

4. Use the `-i` flag to include response headers in the output:

   ```bash
   curl -i -X PROPFIND -H "Depth: 0" http://localhost:8080/webdav/test.txt
   ```

5. When testing lock functionality, always save the lock token from the LOCK response, as it's needed for subsequent operations.

6. Test operations with both missing and invalid lock tokens to ensure proper error handling.

7. When testing directory operations with locks, verify that the lock applies correctly to all depths specified.
