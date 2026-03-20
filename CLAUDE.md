# CLAUDE.md — To-do List App

This file provides Claude with context about this project: its architecture, development commands, conventions, and how to work effectively within the codebase.

---

## Project Overview

A user-authenticated task management web application built with Django. Each registered user can create, view, update, delete, and search their own tasks. Tasks are scoped per user and ordered by completion status.

**Tech stack:**
- Backend: Django 4.1.2 (Python)
- Database: PostgreSQL (production via Railway), SQLite (local dev fallback)
- Frontend: Django template language (HTML)
- Auth: Django built-in authentication system

---

## Repository Structure

```
To-do-list-app-1/
├── config/                  # Django project config (settings, urls, wsgi, asgi)
│   ├── settings.py
│   ├── urls.py
│   ├── wsgi.py
│   └── asgi.py
├── todo_list/               # Main Django application
│   ├── models.py            # Task model
│   ├── views.py             # Class-based views (CRUD + auth)
│   ├── urls.py              # App-level URL routing
│   ├── admin.py             # Admin registration
│   ├── tests.py             # Unit tests
│   ├── migrations/          # Database migrations
│   └── templates/todo_list/ # HTML templates
│       ├── login.html
│       ├── register.html
│       ├── main.html
│       ├── task_list.html
│       ├── task.html
│       ├── task_form.html
│       └── task_confirm_delete.html
├── manage.py
├── requirements.txt
├── db.sqlite3               # Local dev database (not for production)
└── README.md
```

---

## Development Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd To-do-list-app-1

# 2. Create and activate a virtual environment
python3 -m venv env
source env/bin/activate        # Linux/macOS
# source env/Scripts/activate  # Windows

# 3. Install dependencies
pip install -r requirements.txt

# 4. Apply migrations
python manage.py migrate

# 5. Start the development server
python manage.py runserver
```

The app will be available at `http://127.0.0.1:8000/`.

---

## Common Commands

| Task | Command |
|------|---------|
| Run dev server | `python manage.py runserver` |
| Apply migrations | `python manage.py migrate` |
| Create migrations | `python manage.py makemigrations` |
| Create superuser | `python manage.py createsuperuser` |
| Run tests | `python manage.py test` |
| Open Django shell | `python manage.py shell` |
| Install dependencies | `pip install -r requirements.txt` |

---

## Data Model

### `Task` (`todo_list/models.py`)

| Field | Type | Notes |
|-------|------|-------|
| `user` | ForeignKey → User | Nullable; cascade delete |
| `title` | CharField (200) | Required |
| `description` | TextField | Optional |
| `complete` | BooleanField | Default: `False` |
| `create` | DateTimeField | Auto-populated on creation |

Tasks are ordered by `complete` (incomplete tasks appear first).

---

## URL Routes

| URL | View | Name |
|-----|------|------|
| `/login/` | `CustomLoginView` | `login` |
| `/logout/` | `LogoutView` | `logout` |
| `/register/` | `RegisterPage` | `register` |
| `/` | `TaskList` | `tasks` |
| `/task/<id>/` | `TaskDetail` | `task` |
| `/task-create/` | `TaskCreate` | `task-create` |
| `/task-update/<id>/` | `TaskUpdate` | `task-update` |
| `/task-delete/<id>/` | `DeleteView` | `task-delete` |

---

## Views Overview (`todo_list/views.py`)

All task views use `LoginRequiredMixin` — unauthenticated users are redirected to `/login/`.

- **`CustomLoginView`** — Extends Django's `LoginView`; redirects authenticated users away.
- **`RegisterPage`** — `UserCreationForm`-based registration; logs user in on success.
- **`TaskList`** — Filters tasks by `request.user`; supports title prefix search via `?search-area=`.
- **`TaskDetail`** — Read-only view of a single task.
- **`TaskCreate`** — Creates a task and binds it to `request.user`.
- **`TaskUpdate`** — Updates title, description, complete status.
- **`DeleteView`** — Confirms then deletes a task.

---

## Authentication

> **Note:** This section is intentionally left incomplete. Authentication approach/recommendations are to be defined separately.

<!-- TODO: Add auth strategy here (e.g. session-based, token-based, third-party OAuth, etc.) -->

---

## Database

**Production:** PostgreSQL hosted on Railway.
**Local dev:** SQLite (`db.sqlite3`) can be used by switching `DATABASES` in `config/settings.py`.

> **Important:** Never commit real database credentials or secrets to version control. Move sensitive values to environment variables using `python-decouple`, `django-environ`, or similar.

---

## Environment Variables (Recommended)

The following values should be stored as environment variables, not hardcoded in `settings.py`:

| Variable | Description |
|----------|-------------|
| `SECRET_KEY` | Django secret key |
| `DEBUG` | `True` for dev, `False` for production |
| `DB_NAME` | PostgreSQL database name |
| `DB_USER` | PostgreSQL username |
| `DB_PASSWORD` | PostgreSQL password |
| `DB_HOST` | PostgreSQL host |
| `DB_PORT` | PostgreSQL port |
| `ALLOWED_HOSTS` | Comma-separated list of allowed hosts |

---

## Code Conventions

- Use Django class-based views (CBVs) — existing views follow this pattern.
- Keep business logic in views or models, not templates.
- All new task-related views must use `LoginRequiredMixin`.
- Templates live in `todo_list/templates/todo_list/`.
- New migrations should be created with `makemigrations` and committed alongside model changes.
- Do not modify `db.sqlite3` — it is a local dev artifact.

---

## Testing

Tests live in `todo_list/tests.py`. Run with:

```bash
python manage.py test
```

When adding new features, add corresponding test cases covering:
- View access (authenticated vs unauthenticated)
- CRUD operations on the `Task` model
- User isolation (users cannot access other users' tasks)

---

## Admin

The `Task` model is registered in Django Admin (`todo_list/admin.py`). Access at `/admin/` after creating a superuser:

```bash
python manage.py createsuperuser
```

---

## Deployment Notes

- Set `DEBUG = False` in production.
- Populate `ALLOWED_HOSTS` with your domain(s).
- Run `python manage.py collectstatic` if serving static files.
- Use a production-grade WSGI server (e.g. Gunicorn) behind a reverse proxy (e.g. Nginx).
- Database is currently configured for Railway (PostgreSQL) — ensure env vars are set in the Railway dashboard.
