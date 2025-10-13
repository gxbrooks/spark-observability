#!/usr/bin/env python3
"""
Create admin user in JupyterHub with NativeAuthenticator
"""
import sys
import sqlite3
import bcrypt
import uuid

# Configuration (will be replaced by Ansible template variables)
ADMIN_USER = "{{ jupyterhub_admin_user }}"
ADMIN_EMAIL = "{{ jupyterhub_admin_email }}"
ADMIN_PASSWORD = "{{ jupyterhub_admin_password }}"
DB_PATH = "/srv/jupyterhub/jupyterhub.sqlite"

def main():
    try:
        # Connect to database
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Check if admin user exists in both tables
        cursor.execute('SELECT name FROM users WHERE name=?', (ADMIN_USER,))
        existing_user = cursor.fetchone()
        
        cursor.execute('SELECT username FROM users_info WHERE username=?', (ADMIN_USER,))
        existing_auth = cursor.fetchone()
        
        if existing_user and existing_auth:
            print(f'Admin user "{ADMIN_USER}" already exists with credentials, skipping')
            return 0
        
        # Clean up partial entries
        if existing_user or existing_auth:
            cursor.execute('DELETE FROM users WHERE name=?', (ADMIN_USER,))
            cursor.execute('DELETE FROM users_info WHERE username=?', (ADMIN_USER,))
            conn.commit()
        
        # Create admin user in users table with cookie_id
        cookie_id = str(uuid.uuid4())
        cursor.execute(
            "INSERT INTO users (name, admin, created, last_activity, cookie_id) VALUES (?, 1, datetime('now'), datetime('now'), ?)",
            (ADMIN_USER, cookie_id)
        )
        
        # Hash password with bcrypt (NativeAuthenticator stores as BLOB)
        password_hash = bcrypt.hashpw(ADMIN_PASSWORD.encode(), bcrypt.gensalt())
        
        # Create entry in users_info table (NativeAuthenticator table)
        cursor.execute(
            "INSERT INTO users_info (username, password, is_authorized, login_email_sent, email, has_2fa) VALUES (?, ?, 1, 0, ?, 0)",
            (ADMIN_USER, password_hash, ADMIN_EMAIL)
        )
        
        conn.commit()
        conn.close()
        
        print('=' * 60)
        print('✅ Admin user created successfully!')
        print('=' * 60)
        print(f'Username: {ADMIN_USER}')
        print(f'Password: {ADMIN_PASSWORD}')
        print(f'Email: {ADMIN_EMAIL}')
        print('Admin privileges: Yes')
        print('Authorized: Yes (can login immediately)')
        print('=' * 60)
        print('')
        print('Login at: https://Lab2.lan:32443')
        
        return 0
        
    except Exception as e:
        print(f'Error creating admin user: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(main())

