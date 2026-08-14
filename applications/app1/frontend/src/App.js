import React, { useState, useEffect } from 'react';
import axios from 'axios';

const API_BASE = process.env.REACT_APP_API_URL || '/api';

const api = axios.create({
  baseURL: API_BASE,
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const formData = new FormData();
      formData.append('username', email);
      formData.append('password', password);
      const res = await api.post('/token', formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      localStorage.setItem('token', res.data.access_token);
      window.location.reload();
    } catch (err) {
      setError(err.response?.data?.detail || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  const handleRegister = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      await api.post('/register', { email, password });
      setError('Registration successful! Please login.');
    } catch (err) {
      setError(err.response?.data?.detail || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-form card">
      <h2>Task Manager</h2>
      {error && <div className="alert alert-danger">{error}</div>}
      <form onSubmit={handleLogin}>
        <div className="form-group">
          <label>Email</label>
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </div>
        <div className="form-group">
          <label>Password</label>
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </div>
        <button type="submit" className="btn btn-primary" style={{width: '100%', marginBottom: '10px'}} disabled={loading}>
          {loading ? 'Logging in...' : 'Login'}
        </button>
      </form>
      <p>Don't have an account? <button onClick={() => {}} style={{background: 'none', border: 'none', color: '#007bff', cursor: 'pointer', padding: 0}}>Register</button></p>
    </div>
  );
}

function TaskApp() {
  const [tasks, setTasks] = useState([]);
  const [newTask, setNewTask] = useState({ title: '', description: '' });
  const [editingId, setEditingId] = useState(null);
  const [editData, setEditData] = useState({ title: '', description: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    fetchTasks();
  }, []);

  const fetchTasks = async () => {
    try {
      const res = await api.get('/tasks');
      setTasks(res.data);
    } catch (err) {
      setError('Failed to load tasks');
    }
  };

  const createTask = async (e) => {
    e.preventDefault();
    if (!newTask.title.trim()) return;
    try {
      const res = await api.post('/tasks', newTask);
      setTasks([res.data, ...tasks]);
      setNewTask({ title: '', description: '' });
    } catch (err) {
      setError('Failed to create task');
    }
  };

  const updateTask = async (id) => {
    try {
      const res = await api.put(`/tasks/${id}`, editData);
      setTasks(tasks.map(t => t.id === id ? res.data : t));
      setEditingId(null);
    } catch (err) {
      setError('Failed to update task');
    }
  };

  const toggleComplete = async (task) => {
    try {
      const res = await api.put(`/tasks/${task.id}`, { completed: task.completed ? 0 : 1 });
      setTasks(tasks.map(t => t.id === task.id ? res.data : t));
    } catch (err) {
      setError('Failed to update task');
    }
  };

  const deleteTask = async (id) => {
    if (!window.confirm('Delete this task?')) return;
    try {
      await api.delete(`/tasks/${id}`);
      setTasks(tasks.filter(t => t.id !== id));
    } catch (err) {
      setError('Failed to delete task');
    }
  };

  const startEdit = (task) => {
    setEditingId(task.id);
    setEditData({ title: task.title, description: task.description || '' });
  };

  const cancelEdit = () => {
    setEditingId(null);
    setEditData({ title: '', description: '' });
  };

  const logout = () => {
    localStorage.removeItem('token');
    window.location.reload();
  };

  return (
    <div>
      <nav className="navbar">
        <div className="navbar-brand">Task Manager</div>
        <div className="navbar-nav">
          <button onClick={logout} className="btn btn-secondary">Logout</button>
        </div>
      </nav>
      <div className="container">
        {error && <div className="alert alert-danger">{error}</div>}
        
        <div className="card">
          <h3>Create Task</h3>
          <form onSubmit={createTask}>
            <div className="form-group">
              <label>Title</label>
              <input
                type="text"
                value={newTask.title}
                onChange={(e) => setNewTask({...newTask, title: e.target.value})}
                placeholder="Task title"
                required
              />
            </div>
            <div className="form-group">
              <label>Description</label>
              <textarea
                value={newTask.description}
                onChange={(e) => setNewTask({...newTask, description: e.target.value})}
                placeholder="Task description (optional)"
                rows={3}
              />
            </div>
            <button type="submit" className="btn btn-primary">Add Task</button>
          </form>
        </div>

        <div className="card">
          <h3>Tasks ({tasks.length})</h3>
          {tasks.length === 0 ? (
            <p style={{color: '#6c757d', textAlign: 'center', padding: '20px'}}>No tasks yet. Create one above!</p>
          ) : (
            <ul className="task-list">
              {tasks.map(task => (
                <li key={task.id} className="task-item">
                  {editingId === task.id ? (
                    <>
                      <input
                        type="checkbox"
                        className="task-checkbox"
                        checked={task.completed}
                        onChange={() => {}}
                      />
                      <div className="task-content" style={{flex: 1}}>
                        <div className="form-group" style={{marginBottom: '8px'}}>
                          <input
                            type="text"
                            value={editData.title}
                            onChange={(e) => setEditData({...editData, title: e.target.value})}
                          />
                        </div>
                        <div className="form-group" style={{marginBottom: '8px'}}>
                          <textarea
                            value={editData.description}
                            onChange={(e) => setEditData({...editData, description: e.target.value})}
                            rows={2}
                          />
                        </div>
                        <div className="task-actions">
                          <button onClick={() => updateTask(task.id)} className="btn btn-primary btn-sm">Save</button>
                          <button onClick={cancelEdit} className="btn btn-secondary btn-sm">Cancel</button>
                        </div>
                      </div>
                    </>
                  ) : (
                    <>
                      <input
                        type="checkbox"
                        className="task-checkbox"
                        checked={task.completed}
                        onChange={() => toggleComplete(task)}
                      />
                      <div className="task-content">
                        <div className={`task-title ${task.completed ? 'completed' : ''}`}>
                          {task.title}
                        </div>
                        {task.description && (
                          <div className="task-description">{task.description}</div>
                        )}
                      </div>
                      <div className="task-actions">
                        <button onClick={() => startEdit(task)} className="btn btn-secondary btn-sm">Edit</button>
                        <button onClick={() => deleteTask(task.id)} className="btn btn-danger btn-sm">Delete</button>
                      </div>
                    </>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}

function App() {
  const token = localStorage.getItem('token');
  return token ? <TaskApp /> : <Login />;
}

export default App;