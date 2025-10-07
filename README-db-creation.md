# PostgreSQL Database Creation Ansible Playbook

This Ansible playbook automates the creation of a PostgreSQL database and user, and grants all necessary privileges to the user on the database and its public schema.

## Features
- Installs the required Python PostgreSQL driver (`psycopg2-binary`)
- Creates a PostgreSQL database with specified name and encoding
- Creates a PostgreSQL user with specified username and password
- Grants all privileges on the database to the user
- Grants USAGE and all privileges on the public schema to the user
- Tests the connection to the database as the new user
- Displays a summary of the setup

## Variables
You can customize the following variables in the playbook:

- `postgres_host`: Hostname or IP address of the PostgreSQL server
- `postgres_port`: Port number of the PostgreSQL server
- `postgres_admin_user`: Admin user with privileges to create databases and users
- `postgres_admin_password`: Password for the admin user
- `db_name`: Name of the database to create
- `db_user`: Name of the user to create
- `db_password`: Password for the new user

## Sample Usage

1. Edit the variables at the top of `postgresql-db-creation.yml` to match your environment and desired database/user credentials.

2. Run the playbook with Ansible:

```sh
ansible-playbook postgresql-db-creation.yml
```

## Example Variable Section
```yaml
vars:
  postgres_host: "10.0.2.20"
  postgres_port: "5432"
  postgres_admin_user: "postgres"
  postgres_admin_password: "postgres_password"
  db_name: "my_app_db"
  db_user: "my_app_user"
  db_password: "my_app_password"
```

## Requirements
- Ansible installed on your local machine
- Access to the target PostgreSQL server
- The admin user must have sufficient privileges to create databases and users

## Notes
- The playbook is designed to be generic and reusable for any PostgreSQL database and user creation scenario.
- Make sure the target PostgreSQL server allows connections from the machine running Ansible.

---

ansible-playbook postgresql-db-creation.yml \
  --extra-vars "db_name=document_db db_user=doc_user db_password=doc_password postgres_host=10.0.2.20 postgres_admin_password=postgres_password"

Feel free to modify the playbook to suit your specific requirements!

