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

## GET and PUT Operations

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

