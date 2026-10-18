// Login and Registration form handlers - TypeScript version

interface ErrorMap {
  [key: string]: string | string[];
}

interface ApiResponse {
  status: string;
  token?: string;
  errors?: ErrorMap;
}

interface LoginData {
  email: string;
  password: string;
}

interface RegisterData extends LoginData {
  name: string;
}

// Utility to display errors in a <div class="error-messages"></div>
function displayErrors(container: HTMLElement | null, errors: ErrorMap): void {
  if (!container) return;
  
  container.innerHTML = ""; // clear previous errors
  Object.entries(errors).forEach(([field, messages]) => {
    const msgArray = Array.isArray(messages) ? messages : [messages];
    msgArray.forEach((msg: string) => {
      const div = document.createElement("div");
      div.classList.add("error-message");
      div.textContent = `${field}: ${msg}`;
      container.appendChild(div);
    });
  });
}

async function makeApiRequest(url: string, data: LoginData | RegisterData): Promise<ApiResponse> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data)
  });
  
  return response.json();
}

function handleSuccessfulAuth(token: string): void {
  localStorage.setItem("authToken", token);
  window.location.href = "/dashboard";
}

function getFormValue(form: HTMLFormElement, name: string): string {
  const input = form.querySelector(`input[name='${name}']`) as HTMLInputElement;
  return input?.value || '';
}

function getErrorContainer(form: HTMLFormElement): HTMLElement | null {
  return form.querySelector(".error-messages");
}

document.addEventListener("DOMContentLoaded", () => {
  const loginForm = document.getElementById("login-form") as HTMLFormElement;
  const registerForm = document.getElementById("register-form") as HTMLFormElement;

  // ------------------ Login ------------------
  if (loginForm) {
    loginForm.addEventListener("submit", async (e: Event) => {
      e.preventDefault();
      
      const email = getFormValue(loginForm, 'email');
      const password = getFormValue(loginForm, 'password');
      const errorContainer = getErrorContainer(loginForm);

      try {
        const data = await makeApiRequest("/api/game/login", { email, password });

        if (data.status === "ok" && data.token) {
          handleSuccessfulAuth(data.token);
        } else {
          displayErrors(errorContainer, data.errors || { login: "Unknown error" });
        }
      } catch (err) {
        console.error('Login error:', err);
        displayErrors(errorContainer, { network: "Network error" });
      }
    });
  }

  // ------------------ Register ------------------
  if (registerForm) {
    registerForm.addEventListener("submit", async (e: Event) => {
      e.preventDefault();
      
      const email = getFormValue(registerForm, 'email');
      const password = getFormValue(registerForm, 'password');
      const name = getFormValue(registerForm, 'name');
      const errorContainer = getErrorContainer(registerForm);

      try {
        const data = await makeApiRequest("/api/game/register", { email, password, name });

        if (data.status === "ok" && data.token) {
          handleSuccessfulAuth(data.token);
        } else {
          displayErrors(errorContainer, data.errors || { register: "Unknown error" });
        }
      } catch (err) {
        console.error('Registration error:', err);
        displayErrors(errorContainer, { network: "Network error" });
      }
    });
  }
});