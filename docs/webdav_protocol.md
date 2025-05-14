# WebDAV Protocol

WebDAV (Web Distributed Authoring and Versioning) is an extension of the HTTP protocol that enables collaborative editing and management of files on web servers. Distributed authoring means multiple users can collaboratively create, edit and manage content on a web server remotely.

Methods in webDav:

- `GET` - Retrieve a resource
- `PUT` - Create or update a resource
- `DELETE` - Remove a resource
- `MKCOL` - Create a collection/directory
- `PROPFIND` - Retrieve properties of resources
- `PROPPATCH` - Set/modify properties of resources
- `LOCK` - Place a lock on a resource
- `UNLOCK` - Remove a lock from a resource
- `COPY` - Copy a resource
- `MOVE` - Move a resource

## Property Management

Properties in WebDAV are metadata associated with resources. They provide additional information about resources beyond just their content. WebDAV defines two types of properties:

1. Live Properties

   - Maintained and controlled by the server
   - Read-only from client perspective
   - Examples include:
     - getcontentlength (file size)
     - getlastmodified (last modification time)
     - creationdate (resource creation date)
     - resourcetype (collection vs non-collection)
     - getetag (entity tag for caching)
     - getcontenttype (MIME type)

2. Dead Properties
   - Set and maintained by clients
   - Can be modified by clients using PROPPATCH
   - Used for custom metadata
   - Examples include:
     - author
     - description
     - keywords
     - categories
     - custom application-specific properties

Properties can be:

- Retrieved using PROPFIND
- Modified using PROPPATCH (dead properties only)
- Removed using PROPPATCH with removal directive
- Protected from modification via locks

The property system allows WebDAV to support rich metadata management beyond basic file attributes.

### GET

- Does not require XML body or special parameters
- Retrieves a resource from the server
- For collections (directories):
  - Returns HTML page listing contents with links to nested resources
  - Enables browsing directory structure
- For files:
  - Returns file contents directly

### PUT

- Does not require XML body or special parameters
- Creates or updates a resource on the server
- Restrictions:
  - Cannot be used to create collections (use MKCOL instead)
  - Will return 409 Conflict if attempting to PUT to non-existent parent path
  - Parent collection must exist before putting files inside it
  - Cannot create or update resources if target file or parent collection is locked
- Common status codes:
  - 201 Created - New resource created
  - 204 No Content - Existing resource updated
  - 409 Conflict - Parent path does not exist
  - 423 Locked - Resource is locked

### Move

- Moves a resource from one location to another
- Required headers:
  - Destination: Target URI for the move
- Optional headers:
  - Overwrite: "T" to allow overwriting existing resources, "F" to prevent (default "T")
- Automatically moves all children for collections
- Cannot move to a locked resource
- May return XML multistatus response (207) detailing success/failure of individual resources when moving collections
- Common status codes:
  - 201 Created - Resource moved to new location
  - 204 No Content - Resource moved, overwriting existing target
  - 207 Multi-Status - Partial success/failure for collection moves
  - 423 Locked - Source or destination is locked
  - 409 Conflict - Parent of destination does not exist

### Copy

- Creates a duplicate of a resource at a new location
- Required headers:
  - Destination: Target URI for the copy
- Optional headers:
  - Depth: "0" for resource only, "1" for resource and immediate children, "infinity" for recursive copy (default "infinity")
  - Overwrite: "T" to allow overwriting existing resources, "F" to prevent (default "T")
- Recursively copies all children for collections when Depth: infinity
- Cannot copy to a locked resource
- May return XML multistatus response (207) containing results for each resource in collection copies
- Common status codes:
  - 201 Created - Resource copied to new location
  - 204 No Content - Resource copied, overwriting existing target
  - 207 Multi-Status - Partial success/failure for collection copies
  - 423 Locked - Source or destination is locked
  - 409 Conflict - Parent of destination does not exist

### MKCOL

- Creates a new collection (directory) on the server
- Request body must be empty
- Parent collection must exist before creating child collections
- Cannot create a collection where a resource already exists
- Cannot create a collection if target or parent is locked
- Common status codes:
  - 201 Created - Collection created successfully
  - 409 Conflict - Parent collection does not exist or resource exists at location
  - 423 Locked - Target or parent collection is locked
  - 415 Unsupported Media Type - Request contained a body

### PROPFIND

- Retrieves properties for a resource
- request body containing XML specifying which properties to retrieve
- Optional headers:
  - Depth: "0" for resource only, "1" for resource and children, "infinity" for recursive (default "infinity")
- Returns XML multistatus response with property values
- Common status codes:
  - 207 Multi-Status - Properties retrieved successfully
  - 404 Not Found - Resource does not exist

### PROPPATCH

- Modifies properties on a resource
- Request body must contain XML specifying property changes:
  - set: Add or modify properties
  - remove: Delete properties
- Returns XML multistatus response with results of property modifications
- Common status codes:
  - 207 Multi-Status - Properties modified successfully
  - 404 Not Found - Resource does not exist
  - 423 Locked - Resource is locked

### LOCK

- Places a lock on a resource to prevent modifications
- Optional request body containing XML with lock information:
  - lockscope: exclusive or shared
  - locktype: write
  - owner: Lock owner information
- Optional headers:
  - Depth: "0" or "infinity" for recursive locking (default "infinity")
  - Timeout: Lock timeout value (default "Infinite")
- Returns XML response with lock token and details
- Common status codes:
  - 200 OK - Lock created successfully
  - 423 Locked - Resource is already locked
  - 409 Conflict - Cannot create lock

### UNLOCK

- Removes a lock from a resource
- Required headers:
  - Lock-Token: Token of lock to remove
- No request body
- Common status codes:
  - 204 No Content - Lock removed successfully
  - 404 Not Found - Resource or lock not found
  - 400 Bad Request - Missing lock token

### IF parameter

- Used to make requests conditional on locks or ETags
- Header format: If: (<lock-token>) (<lock-token2>)
- Makes method execution conditional on specified lock tokens matching
