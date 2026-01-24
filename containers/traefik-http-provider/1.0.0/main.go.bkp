package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

// Server gerencia o servidor HTTP e suas dependências
type Server struct {
	apiKey     string
	apiUser    string
	apiPass    string
	configPath string
	config     map[string]interface{}
	mu         sync.RWMutex
	lastMod    time.Time
	logger     *slog.Logger
}

// NewServer cria uma nova instância do servidor
func NewServer(apiKey, apiUser, apiPass, configPath string) *Server {
	return &Server{
		apiKey:     apiKey,
		apiUser:    apiUser,
		apiPass:    apiPass,
		configPath: configPath,
		logger:     slog.New(slog.NewJSONHandler(os.Stdout, nil)),
	}
}

// loadConfig carrega e atualiza a configuração do arquivo YAML
func (s *Server) loadConfig() error {
	info, err := os.Stat(s.configPath)
	if err != nil {
		return err
	}

	s.mu.RLock()
	lastMod := s.lastMod
	s.mu.RUnlock()

	// Se não mudou, não recarrega
	if info.ModTime().Equal(lastMod) {
		return nil
	}

	data, err := os.ReadFile(s.configPath)
	if err != nil {
		return err
	}

	var cfg map[string]interface{}
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return err
	}

	s.mu.Lock()
	s.config = cfg
	s.lastMod = info.ModTime()
	s.mu.Unlock()

	s.logger.Info("config loaded", "path", s.configPath, "modTime", info.ModTime())
	return nil
}

// basicAuthMiddleware valida autenticação via Basic Auth
func (s *Server) basicAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, pass, ok := r.BasicAuth()

		if !ok || user != s.apiUser || pass != s.apiPass {
			s.logger.Warn("unauthorized access via basic auth",
				"ip", r.RemoteAddr,
				"path", r.URL.Path,
				"user", user,
			)
			w.Header().Set("WWW-Authenticate", `Basic realm="Traefik HTTP Provider"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}

		next(w, r)
	}
}

// apiAuthMiddleware valida autenticação via API Key
func (s *Server) apiAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("X-API-Key")
		if key == "" || key != s.apiKey {
			s.logger.Warn("unauthorized access via api key",
				"ip", r.RemoteAddr,
				"path", r.URL.Path,
			)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

// handleTraefik retorna a configuração do Traefik em JSON
func (s *Server) handleTraefik(w http.ResponseWriter, r *http.Request) {
	if err := s.loadConfig(); err != nil {
		s.logger.Error("failed to load config", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	s.mu.RLock()
	cfg := s.config
	s.mu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(cfg); err != nil {
		s.logger.Error("failed to encode json", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// handleHealth retorna status de saúde
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func main() {
	// Carrega variáveis de ambiente
	apiKey := os.Getenv("API_KEY")
	apiUser := os.Getenv("API_USER")
	apiPass := os.Getenv("API_PASS")

	// Valida que pelo menos um método de autenticação está configurado
	if apiKey == "" && (apiUser == "" || apiPass == "") {
		slog.Error("nenhum método de autenticação configurado (API_KEY ou API_USER/API_PASS)")
		os.Exit(1)
	}

	configPath := os.Getenv("CONFIG_PATH")
	if configPath == "" {
		configPath = "/config/traefik.yml"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Cria servidor
	srv := NewServer(apiKey, apiUser, apiPass, configPath)

	// Carrega configuração inicial
	if err := srv.loadConfig(); err != nil {
		srv.logger.Error("failed to load initial config", "error", err)
		os.Exit(1)
	}

	// Define rotas
	// Rota principal com API Key (se configurada)
	if apiKey != "" {
		http.HandleFunc("/traefik", srv.apiAuthMiddleware(srv.handleTraefik))
		srv.logger.Info("rota /traefik protegida com API Key")
	}

	// Rota alternativa com Basic Auth (se configurada)
	if apiUser != "" && apiPass != "" {
		http.HandleFunc("/traefik-basic", srv.basicAuthMiddleware(srv.handleTraefik))
		srv.logger.Info("rota /traefik-basic protegida com Basic Auth")
	}

	// Health check sem autenticação
	http.HandleFunc("/health", srv.handleHealth)

	// Informa método de autenticação ativo
	authMethod := "nenhuma"
	if apiKey != "" {
		authMethod = "API Key"
	}
	if apiUser != "" && apiPass != "" {
		if authMethod != "nenhuma" {
			authMethod += " + Basic Auth"
		} else {
			authMethod = "Basic Auth"
		}
	}

	srv.logger.Info("server starting",
		"port", port,
		"auth", authMethod,
		"config", configPath,
	)

	// Inicia servidor
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		srv.logger.Error("server failed", "error", err)
		os.Exit(1)
	}
}