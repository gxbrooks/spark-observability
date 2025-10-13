#!/usr/bin/env python3
"""
Create admin user in JupyterHub via API
"""
import requests
import json
import sys
import time

# Configuration
ADMIN_USER = "{{ jupyterhub_admin_user }}"
ADMIN_PASSWORD = "{{ jupyterhub_admin_password }}"
ADMIN_EMAIL = "{{ jupyterhub_admin_email }}"
HUB_API_URL = "http://localhost:8081/hub/api"

# Get API token from hub
def get_api_token():
    """Get the JupyterHub API token from environment or config"""
    import os
    # For now, we'll create a user via direct hub method
    return None

def create_user_via_hub():
    """Create user by calling JupyterHub's internal methods"""
    try:
        # Import JupyterHub's user management
        from jupyterhub import orm
        from nativeauthenticator.nativeauthenticator import NativeAuthenticator
        from jupyterhub.app import JupyterHub
        
        # Get the database session
        import sqlalchemy as sa
        from sqlalchemy import create_engine
        from sqlalchemy.orm import sessionmaker
        
        db_url = 'sqlite:////srv/jupyterhub/jupyterhub.sqlite'
        engine = create_engine(db_url)
        Session = sessionmaker(bind=engine)
        db = Session()
        
        # Check if user exists
        existing = db.query(orm.User).filter(orm.User.name == ADMIN_USER).first()
        if existing:
            print(f'Admin user "{ADMIN_USER}" already exists')
            db.close()
            return 0
        
        # Create user
        user = orm.User(name=ADMIN_USER, admin=True)
        db.add(user)
        db.commit()
        
        # Use NativeAuthenticator to set password
        auth = NativeAuthenticator()
        auth.create_user(ADMIN_USER, ADMIN_PASSWORD, email=ADMIN_EMAIL)
        
        print('=' * 50)
        print('Admin user created successfully!')
        print('=' * 50)
        print(f'Username: {ADMIN_USER}')
        print(f'Email: {ADMIN_EMAIL}')
        print('Password: Set (hashed)')
        print('Admin: Yes')
        print('Authorized: Yes')
        print('=' * 50)
        
        db.close()
        return 0
        
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(create_user_via_hub())

